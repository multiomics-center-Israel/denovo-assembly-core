"""Email notification helper.

Two ways to send mail:
  1. Programmatic: build a Config and call send_email(cfg, subject, body).
  2. CLI for shell wrappers: pass --config <project.yaml> "Subject" "Body".

The CLI mode is what bin/run_pipeline.sh calls when a run finishes.
"""

import smtplib
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


def send_email(cfg, subject: str, body: str, html_body: str = None) -> bool:
    """Send an email using the SMTP host configured in cfg.

    Returns True on success, False otherwise. Never raises.
    """
    if not getattr(cfg, "NOTIFY_ENABLED", True):
        return False
    try:
        if html_body:
            msg = MIMEMultipart("alternative")
            msg.attach(MIMEText(body, "plain"))
            msg.attach(MIMEText(html_body, "html"))
        else:
            msg = MIMEText(body, "plain")

        msg["Subject"] = subject
        msg["From"] = cfg.FROM_ADDR
        msg["To"] = cfg.TO_ADDR
        msg["Date"] = datetime.now().strftime("%a, %d %b %Y %H:%M:%S %z")

        with smtplib.SMTP(cfg.SMTP_HOST, cfg.SMTP_PORT, timeout=30) as server:
            server.ehlo()
            try:
                server.starttls()
                server.ehlo()
            except smtplib.SMTPException:
                # Some relays don't offer STARTTLS; that's OK on a trusted LAN.
                pass
            server.sendmail(cfg.FROM_ADDR, [cfg.TO_ADDR], msg.as_string())

        print(f"Email sent to {cfg.TO_ADDR}")
        return True
    except Exception as e:
        print(f"Email failed: {e}")
        return False


def _cli():
    import argparse
    from .config import Config

    parser = argparse.ArgumentParser(description="Send a pipeline notification email.")
    parser.add_argument("--config", required=True, help="Path to project.yaml")
    parser.add_argument("subject", help="Email subject line")
    parser.add_argument("body", nargs="?", default="", help="Email body text")
    parser.add_argument("--test", action="store_true", help="Send a test email and exit")
    args = parser.parse_args()

    cfg = Config(args.config)
    if args.test:
        ok = send_email(
            cfg,
            f"[Pipeline Test] {cfg.SPECIES_SHORT} notification",
            (
                "This is a test email from the genome assembly pipeline.\n"
                f"Sent at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                "If you received this, email notifications are working."
            ),
        )
    else:
        ok = send_email(cfg, args.subject, args.body)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    _cli()
