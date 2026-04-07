"""
Contact Lens GenAI Remediation for AWS GovCloud
Replaces missing Contact Lens GenAI features (summarization, semantic categorization)
with a custom Amazon Bedrock pipeline.

Triggered by S3 PutObject when Contact Lens deposits a post-call transcript.
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
SUMMARY_BUCKET = os.environ["SUMMARY_BUCKET"]
SUMMARY_PREFIX = os.environ.get("SUMMARY_PREFIX", "summaries/")
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]

bedrock_config = Config(retries={"max_attempts": 3, "mode": "adaptive"})
bedrock = boto3.client("bedrock-runtime", config=bedrock_config)
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DYNAMODB_TABLE)

SUMMARIZATION_PROMPT = """You are an AI assistant for a contact center.
Analyze the following contact center transcript and provide:

1. **Contact Summary**: A concise 2-3 sentence summary of the interaction, including the caller's
   primary reason for calling, key actions taken by the agent, and the resolution or next steps.

2. **Semantic Category**: Classify this contact into exactly ONE primary category from this list:
   - Sales Inquiry
   - Account Management
   - Technical Support
   - Billing/Payment
   - Order Status
   - Product Information
   - Complaint/Escalation
   - Service Request
   - Returns/Refunds
   - General Information
   - Other

3. **Intent**: The caller's specific intent in 5 words or fewer (e.g., "Check order delivery status").

4. **Sentiment**: Overall caller sentiment: Positive, Neutral, Negative, or Escalated.

5. **Disposition**: How the contact ended: Resolved, Transferred, Callback Scheduled, Unresolved.

Respond ONLY with valid JSON in this exact format:
{
  "summary": "...",
  "category": "...",
  "intent": "...",
  "sentiment": "...",
  "disposition": "...",
  "key_topics": ["topic1", "topic2"],
  "follow_up_required": true/false
}

TRANSCRIPT:
"""


def extract_transcript_text(transcript_data):
    """Extract readable text from Contact Lens transcript JSON format.

    Supports multiple formats:
    - Contact Lens post-call analysis JSON (has "Transcript" with "Participants" and "Content")
    - Contact Lens real-time analysis segments
    - Simple transcript format (array of segments with ParticipantId/Content)
    - Raw transcript string
    """
    # Contact Lens post-call analysis format: has Channel, Participants, and Transcript
    if "Channel" in transcript_data and "Participants" in transcript_data:
        participants = {
            p.get("ParticipantId", ""): p.get("ParticipantRole", "UNKNOWN")
            for p in transcript_data.get("Participants", [])
        }
        segments = transcript_data.get("Transcript", [])
        lines = []
        for seg in segments:
            pid = seg.get("ParticipantId", "")
            role = participants.get(pid, "UNKNOWN").upper()
            content = seg.get("Content", "")
            if content:
                lines.append(f"{role}: {content}")
        if lines:
            return "\n".join(lines)

    # Simple transcript array format
    segments = transcript_data.get("Transcript", [])
    if not segments:
        segments = transcript_data.get("transcript", [])

    lines = []
    for segment in segments:
        participant = segment.get("ParticipantId", segment.get("participantId", "UNKNOWN"))
        content = segment.get("Content", segment.get("content", ""))
        if content:
            role = "AGENT" if "agent" in participant.lower() else "CALLER"
            lines.append(f"{role}: {content}")

    if not lines:
        raw = transcript_data.get("RawTranscript", transcript_data.get("rawTranscript", ""))
        if raw:
            return raw
        return json.dumps(transcript_data)

    return "\n".join(lines)


def invoke_bedrock(transcript_text):
    """Invoke Bedrock with the transcript for summarization and categorization."""
    prompt = SUMMARIZATION_PROMPT + transcript_text

    body = json.dumps({
        "inputText" if "titan" in BEDROCK_MODEL_ID.lower() else "messages": (
            prompt if "titan" in BEDROCK_MODEL_ID.lower()
            else [{"role": "user", "content": [{"text": prompt}]}]
        ),
        **_model_params()
    })

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=body,
    )

    response_body = json.loads(response["body"].read())
    return _extract_response_text(response_body)


def _model_params():
    """Return model-specific inference parameters."""
    if "titan" in BEDROCK_MODEL_ID.lower():
        return {
            "textGenerationConfig": {
                "maxTokenCount": 1024,
                "temperature": 0.1,
                "topP": 0.9,
            }
        }
    if "nova" in BEDROCK_MODEL_ID.lower():
        return {
            "inferenceConfig": {
                "max_new_tokens": 1024,
                "temperature": 0.1,
                "top_p": 0.9,
            }
        }
    # Anthropic Claude format
    return {
        "max_tokens": 1024,
        "temperature": 0.1,
        "anthropic_version": "bedrock-2023-05-31",
    }


def _extract_response_text(response_body):
    """Extract text from model-specific response format."""
    # Nova / Converse-style
    if "output" in response_body and "message" in response_body.get("output", {}):
        content = response_body["output"]["message"]["content"]
        return content[0]["text"] if content else ""
    # Titan
    if "results" in response_body:
        return response_body["results"][0]["outputText"]
    # Claude Messages API
    if "content" in response_body:
        return response_body["content"][0]["text"]
    # Fallback
    return json.dumps(response_body)


def parse_ai_response(response_text):
    """Parse the JSON response from Bedrock, handling markdown code blocks."""
    text = response_text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        logger.warning("Failed to parse AI response as JSON, using raw text")
        return {
            "summary": text[:500],
            "category": "Other",
            "intent": "Unknown",
            "sentiment": "Neutral",
            "disposition": "Unresolved",
            "key_topics": [],
            "follow_up_required": False,
        }


def write_to_dynamodb(contact_id, timestamp, analysis):
    """Write the structured analysis to DynamoDB."""
    item = {
        "contactId": contact_id,
        "timestamp": timestamp,
        "summary": analysis.get("summary", ""),
        "category": analysis.get("category", "Other"),
        "intent": analysis.get("intent", ""),
        "sentiment": analysis.get("sentiment", "Neutral"),
        "disposition": analysis.get("disposition", ""),
        "keyTopics": analysis.get("key_topics", []),
        "followUpRequired": analysis.get("follow_up_required", False),
        "modelId": BEDROCK_MODEL_ID,
        "processedAt": datetime.now(timezone.utc).isoformat(),
    }
    table.put_item(Item=item)
    return item


def write_to_s3(contact_id, timestamp, analysis):
    """Write the summary JSON to the output S3 bucket."""
    key = f"{SUMMARY_PREFIX}{contact_id}/{timestamp}.json"
    s3.put_object(
        Bucket=SUMMARY_BUCKET,
        Key=key,
        Body=json.dumps(analysis, indent=2),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
    )
    return key


def lambda_handler(event, context):
    """Main Lambda handler triggered by S3 PutObject."""
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        logger.info("Processing transcript: s3://%s/%s", bucket, key)

        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            transcript_data = json.loads(response["Body"].read())
        except (ClientError, json.JSONDecodeError) as e:
            logger.error("Failed to read transcript %s: %s", key, e)
            continue

        contact_id = (
            transcript_data.get("CustomerMetadata", {}).get("ContactId")
            or transcript_data.get("ContactId")
            or transcript_data.get("contactId")
            or key.split("/")[-1].replace(".json", "")
        )
        timestamp = datetime.now(timezone.utc).isoformat()

        transcript_text = extract_transcript_text(transcript_data)
        logger.info("Transcript length: %d characters for contact %s", len(transcript_text), contact_id)

        try:
            response_text = invoke_bedrock(transcript_text)
            analysis = parse_ai_response(response_text)
        except ClientError as e:
            logger.error("Bedrock invocation failed for %s: %s", contact_id, e)
            continue

        analysis["contactId"] = contact_id
        analysis["sourceKey"] = f"s3://{bucket}/{key}"

        dynamo_item = write_to_dynamodb(contact_id, timestamp, analysis)
        s3_key = write_to_s3(contact_id, timestamp, analysis)

        logger.info(
            "Processed contact %s — category: %s, sentiment: %s, output: s3://%s/%s",
            contact_id, analysis.get("category"), analysis.get("sentiment"),
            SUMMARY_BUCKET, s3_key
        )

    return {"statusCode": 200, "body": "Processed successfully"}
