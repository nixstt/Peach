import logging
import os
from email.message import EmailMessage
from urllib.parse import unquote_plus

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
sesv2 = boto3.client("sesv2")


def handler(event: dict, context: object) -> dict[str, int]:
    log.info("report-mailer triggered trigger=s3")
    records = event["Records"]
    sender = os.environ["REPORT_SENDER"]
    recipients = [
        address.strip()
        for address in os.environ["REPORT_RECIPIENTS"].replace(";", ",").split(",")
        if address.strip()
    ]
    if not recipients:
        raise RuntimeError("REPORT_RECIPIENTS must contain at least one address")

    sent = 0
    for record in records:
        s3_record = record["s3"]
        bucket = s3_record["bucket"]["name"]
        key = unquote_plus(s3_record["object"]["key"])
        log.info("report-mailer object bucket=%s key=%s", bucket, key)
        report = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        filename = key.rsplit("/", 1)[-1]
        message = EmailMessage()
        message["Subject"] = f"Weekly meeting report {filename.removesuffix('.csv')}"
        message["From"] = sender
        message["To"] = ", ".join(recipients)
        message.set_content("Your weekly meeting report is attached.")
        message.add_attachment(
            report,
            maintype="text",
            subtype="csv",
            filename=filename,
        )
        sesv2.send_email(
            FromEmailAddress=sender,
            Destination={"ToAddresses": recipients},
            Content={"Raw": {"Data": message.as_bytes()}},
        )
        sent += 1
    return {"sent": sent}
