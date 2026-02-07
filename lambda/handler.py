import json
import os
import logging
import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Bedrock client
br = boto3.client("bedrock-agent-runtime")

# Configuration
KB_ID = os.environ["TF_VAR_KB_ID"]
MODEL_ARN = os.environ["TF_VAR_MODEL_ARN"]
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", "8000"))
MAX_Q_CHARS = int(os.environ.get("MAX_Q_CHARS", "800"))

# Parse allowed origins safely (empty env var -> empty list, strips whitespace)
_raw_origins = os.environ.get("ALLOWED_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _raw_origins.split(",") if o.strip()]


def _resp(status: int, body: dict, origin: str = None):
    """Build secure HTTP response with proper headers"""
    headers = {
        "content-type": "application/json",
        "x-content-type-options": "nosniff",
        "x-frame-options": "DENY",
    }

    # Only allow whitelisted origins
    if origin and ALLOWED_ORIGINS and origin in ALLOWED_ORIGINS:
        headers["access-control-allow-origin"] = origin
        headers["access-control-allow-headers"] = "content-type, authorization"
        headers["access-control-allow-methods"] = "POST, OPTIONS"
        headers["access-control-max-age"] = "600"

    return {
        "statusCode": status,
        "headers": headers,
        "body": json.dumps(body),
    }


def handler(event, context):
    """Lambda handler for RAG chatbot"""

    # Headers can be normalized; handle both cases
    headers = event.get("headers") or {}
    origin = headers.get("origin") or headers.get("Origin")

    # Handle CORS preflight
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    if method == "OPTIONS":
        # For 204, don't send a body
        resp = _resp(204, {}, origin)
        resp["body"] = ""
        return resp

    # Request size check (bytes, not chars)
    raw = event.get("body") or "{}"
    raw_bytes = raw.encode("utf-8") if isinstance(raw, str) else b""
    if isinstance(raw, str) and len(raw_bytes) > MAX_BODY_BYTES:
        logger.warning(f"Request too large: {len(raw_bytes)} bytes")
        return _resp(413, {"error": "Request too large"}, origin)

    request_id = event.get("requestContext", {}).get("requestId", "unknown")

    try:
        # Parse request
        payload = json.loads(raw) if isinstance(raw, str) else (raw or {})

        # Extract and validate query
        q = (payload.get("q") or payload.get("question") or "").strip()

        if not q:
            return _resp(400, {"error": "Missing 'q' in JSON body", "request_id": request_id}, origin)

        if len(q) > MAX_Q_CHARS:
            return _resp(
                400,
                {"error": f"Question too long (max {MAX_Q_CHARS} chars)", "request_id": request_id},
                origin,
            )

        # Log request (sanitized)
        logger.info(f"Processing query, request_id={request_id}, query_len={len(q)}")

        # Call Bedrock KB (matches diagram)
        r = br.retrieve_and_generate(
            input={"text": q},
            retrieveAndGenerateConfiguration={
                "type": "KNOWLEDGE_BASE",
                "knowledgeBaseConfiguration": {
                    "knowledgeBaseId": KB_ID,
                    "modelArn": MODEL_ARN,
                },
            },
        )

        answer = r.get("output", {}).get("text", "")
        citations = r.get("citations", [])

        # Cap citations
        if isinstance(citations, list) and len(citations) > 3:
            citations = citations[:3]

        logger.info(f"Successfully processed request_id={request_id}")
        return _resp(200, {"answer": answer, "citations": citations, "request_id": request_id}, origin)

    except json.JSONDecodeError as e:
        logger.warning(f"Invalid JSON, request_id={request_id}: {e}")
        return _resp(400, {"error": "Invalid JSON format", "request_id": request_id}, origin)

    except ClientError as e:
        logger.error(f"Bedrock error, request_id={request_id}: {e}", exc_info=True)
        return _resp(502, {"error": "Unable to process request", "request_id": request_id}, origin)

    except Exception as e:
        logger.error(f"Unexpected error, request_id={request_id}: {str(e)}", exc_info=True)
        return _resp(500, {"error": "Internal server error", "request_id": request_id}, origin)