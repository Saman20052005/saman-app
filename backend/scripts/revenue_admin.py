"""
Administrative CLI & Operations Tool for Saman Revenue.
Subsystem: Saman Revenue — Operations, Reconciliation & Audited Grants (CP-10).

OPERATIONAL ACCESS BOUNDARY:
This CLI serves as the authoritative operational interface for revenue reconciliation
and audited manual grants. Administrative mutation is strictly omitted from the public
HTTP router to prevent unauthorized actions.

Usage:
    # 1. Read-only Discrepancy Scan
    python -m backend.scripts.revenue_admin scan [--user <user_id>] [--entity <entity_type>] [--limit <n>]

    # 2. Dry-Run Plan Generation
    python -m backend.scripts.revenue_admin plan [--user <user_id>] [--output-json <path>]

    # 3. Explicit Controlled Plan Application
    python -m backend.scripts.revenue_admin apply --plan-id <plan_id> --actor <operator_name>

    # 4. Audited Manual Grant
    python -m backend.scripts.revenue_admin grant --actor <operator> --user <user_id> --benefit <benefit_id> \\
        --valid-days <n> --reason <reason> --ticket <ticket_ref> --idempotency-key <key>

    # 5. Audited Manual Revocation
    python -m backend.scripts.revenue_admin revoke --actor <operator> --grant-id <grant_id> \\
        --reason <reason> --ticket <ticket_ref> --idempotency-key <key>

    # 6. View Audit Log
    python -m backend.scripts.revenue_admin audit [--user <user_id>] [--actor <operator>] [--limit <n>]

    # 7. Recover Interrupted Audits
    python -m backend.scripts.revenue_admin recover-audits
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone, timedelta
import json
import logging
import os
import sys
from typing import Any, Dict, List, Optional

from backend.app.models.revenue import (
    ManualGrantRequest,
    ManualGrantRevokeRequest,
    ReconciliationActionType,
    ReconciliationPlanStatus,
)
from backend.app.services.reconciliation_service import (
    ReconciliationScanner,
    ReconciliationService,
)
from backend.app.services.manual_grant_service import (
    ManualEntitlementGrantService,
    IdempotencyConflictError,
    ManualGrantValidationError,
    GrantNotFoundError,
)

logger = logging.getLogger("revenue_admin")


def get_db():
    try:
        from backend.app.database import db
        return db
    except Exception as exc:
        print(f"Error connecting to database: {exc}", file=sys.stderr)
        return None


def cmd_scan(args):
    db = get_db()
    if db is None:
        print("Database is unavailable. Cannot perform reconciliation scan.", file=sys.stderr)
        sys.exit(1)

    scanner = ReconciliationScanner(db=db)
    since = datetime.fromisoformat(args.since) if args.since else None
    until = datetime.fromisoformat(args.until) if args.until else None

    print(f"Running read-only reconciliation scan (user={args.user or 'ALL'}, entity={args.entity or 'ALL'})...")
    findings = scanner.scan(
        scope_user_id=args.user,
        scope_entity_type=args.entity,
        since=since,
        until=until,
        limit=args.limit,
    )

    print(f"\nScan complete. Total findings detected: {len(findings)}\n")
    if not findings:
        print("✅ No discrepancies detected. Subsystem consistency verified.")
        return

    print(f"{'Finding ID':<24} | {'Severity':<8} | {'Type':<32} | {'Entity':<10} | {'Review Required':<15}")
    print("-" * 105)
    for f in findings:
        req_rev = "YES" if f.requires_manual_review else "NO"
        print(f"{f.finding_id:<24} | {f.severity.value:<8} | {f.finding_type.value:<32} | {f.entity_type:<10} | {req_rev:<15}")
        print(f"  Description: {f.description}")
        print(f"  Action:      {f.proposed_action.value}")
        if f.evidence_references:
            print(f"  Evidence:    {json.dumps(f.evidence_references)}")
        print()


def cmd_plan(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    service = ReconciliationService(db=db)
    since = datetime.fromisoformat(args.since) if args.since else None
    until = datetime.fromisoformat(args.until) if args.until else None

    print(f"Generating dry-run reconciliation plan (user={args.user or 'ALL'})...")
    plan = service.generate_plan(
        scope_user_id=args.user,
        scope_entity_type=args.entity,
        since=since,
        until=until,
        limit=args.limit,
    )

    plan_id = service.save_plan(plan)
    print(f"\nReconciliation Plan Created: {plan_id}")
    print(f"  Status:               {plan.status.value}")
    print(f"  Total Findings:       {plan.total_findings}")
    print(f"  Actionable Items:     {plan.actionable_count}")
    print(f"  Manual Review Items:  {plan.manual_review_count}")
    print(f"  Prospective Actions:  {json.dumps(plan.expected_state.get('prospective_mutations', {}))}")

    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as f:
            f.write(plan.model_dump_json(indent=2))
        print(f"  Saved plan details to: {args.output_json}")

    print("\nDRY-RUN COMPLETE: Zero database mutations applied.")
    print(f"To execute this plan under CAS verification, run:")
    print(f"  python -m backend.scripts.revenue_admin apply --plan-id {plan_id} --actor <operator_name>")


def cmd_apply(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    service = ReconciliationService(db=db)
    actor = args.actor or os.environ.get("USERNAME") or os.environ.get("USER") or "operator"

    print(f"Applying reconciliation plan '{args.plan_id}' with actor '{actor}' (CAS precondition enforced)...")
    try:
        res = service.apply_plan(
            plan_id=args.plan_id,
            actor=actor,
            max_actions=args.max_actions,
        )
    except Exception as exc:
        print(f"❌ Plan application failed: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"\nPlan Application Complete:")
    print(f"  Plan ID:           {res.plan_id}")
    print(f"  Status:            {res.status.value}")
    print(f"  Total Actions:     {res.total_actions}")
    print(f"  Applied Actions:   {res.applied_actions}")
    print(f"  Aborted (CAS):     {res.aborted_actions}")
    print(f"  Failed:            {res.failed_actions}")
    print(f"  Manual Review:     {res.manual_review_items}")
    print(f"  Duration:          {res.duration_seconds:.3f}s")


def cmd_grant(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    now = datetime.now(timezone.utc)
    if args.valid_until:
        valid_until = datetime.fromisoformat(args.valid_until)
    elif args.valid_days:
        valid_until = now + timedelta(days=args.valid_days)
    else:
        print("Error: Either --valid-days or --valid-until must be specified. Permanent grants are forbidden.", file=sys.stderr)
        sys.exit(1)

    req = ManualGrantRequest(
        idempotency_key=args.idempotency_key,
        actor=args.actor,
        target_user_id=args.user,
        benefit_id=args.benefit,
        valid_from=now,
        valid_until=valid_until,
        reason=args.reason,
        ticket_reference=args.ticket,
    )

    service = ManualEntitlementGrantService(db=db)
    try:
        res = service.grant_entitlement(req, as_of=now)
        status = res.get("status")
        grant_id = res.get("grant_id")
        print(f"✅ Manual Grant Result: {status.upper()}")
        print(f"  Grant ID:        {grant_id}")
        print(f"  User:            {args.user}")
        print(f"  Benefit:         {args.benefit}")
        print(f"  Valid Until:     {valid_until.isoformat()}")
        print(f"  Audit ID:        {res.get('audit_id')}")
    except IdempotencyConflictError as exc:
        print(f"❌ Idempotency Conflict: {exc}", file=sys.stderr)
        sys.exit(1)
    except ManualGrantValidationError as exc:
        print(f"❌ Validation Error: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"❌ Grant Failed: {exc}", file=sys.stderr)
        sys.exit(1)


def cmd_revoke(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    req = ManualGrantRevokeRequest(
        idempotency_key=args.idempotency_key,
        actor=args.actor,
        target_grant_id=args.grant_id,
        reason=args.reason,
        ticket_reference=args.ticket,
    )

    service = ManualEntitlementGrantService(db=db)
    try:
        res = service.revoke_entitlement(req)
        print(f"✅ Manual Revocation Result: {res.get('status').upper()}")
        print(f"  Grant ID:        {args.grant_id}")
        print(f"  Actor:           {args.actor}")
        print(f"  Audit ID:        {res.get('audit_id')}")
    except GrantNotFoundError as exc:
        print(f"❌ Grant Not Found: {exc}", file=sys.stderr)
        sys.exit(1)
    except IdempotencyConflictError as exc:
        print(f"❌ Idempotency Conflict: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"❌ Revocation Failed: {exc}", file=sys.stderr)
        sys.exit(1)


def cmd_audit(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    service = ManualEntitlementGrantService(db=db)
    records = service.get_audit_history(
        target_user_id=args.user,
        actor=args.actor,
        limit=args.limit,
    )

    print(f"Audit log records: {len(records)}\n")
    if not records:
        print("No audit records found matching criteria.")
        return

    print(f"{'Audit ID':<18} | {'Status':<10} | {'Action':<7} | {'Actor':<15} | {'User':<20} | {'Grant ID':<20} | {'Timestamp':<25}")
    print("-" * 125)
    for r in records:
        ts = str(r.get("created_at", ""))
        print(f"{r.get('audit_id', ''):<18} | {r.get('status', ''):<10} | {r.get('action', ''):<7} | {r.get('actor', ''):<15} | {r.get('target_user_id', ''):<20} | {r.get('target_grant_id', ''):<20} | {ts:<25}")
        print(f"  Reason: {r.get('reason')} [Ticket: {r.get('ticket_reference')}]")


def cmd_recover_audits(args):
    db = get_db()
    if db is None:
        print("Database is unavailable.", file=sys.stderr)
        sys.exit(1)

    service = ManualEntitlementGrantService(db=db)
    min_age = getattr(args, "min_age", 60)
    results = service.recover_interrupted_audits(min_age_seconds=min_age)
    print(f"Crash recovery sweep complete. Resolved {len(results)} in-flight audit records.")
    for res in results:
        guidance = f" ({res.get('guidance')})" if res.get('guidance') else ""
        print(f" - Audit '{res.get('audit_id')}': {res.get('resolution')}{guidance}")


def main():
    parser = argparse.ArgumentParser(
        prog="python -m backend.scripts.revenue_admin",
        description="Saman Revenue Operations & Reconciliation Admin CLI (CP-10).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # 1. scan
    p_scan = subparsers.add_parser("scan", help="Run read-only reconciliation scanner.")
    p_scan.add_argument("--user", help="Filter scan by target user ID.")
    p_scan.add_argument("--entity", choices=["event", "grant", "subscription", "bucket", "operation"], help="Filter by entity type.")
    p_scan.add_argument("--since", help="ISO 8601 start timestamp.")
    p_scan.add_argument("--until", help="ISO 8601 end timestamp.")
    p_scan.add_argument("--limit", type=int, default=100, help="Maximum findings to return.")
    p_scan.set_defaults(func=cmd_scan)

    # 2. plan
    p_plan = subparsers.add_parser("plan", help="Generate dry-run reconciliation plan.")
    p_plan.add_argument("--user", help="Filter plan by target user ID.")
    p_plan.add_argument("--entity", choices=["event", "grant", "subscription", "bucket", "operation"], help="Filter by entity type.")
    p_plan.add_argument("--since", help="ISO 8601 start timestamp.")
    p_plan.add_argument("--until", help="ISO 8601 end timestamp.")
    p_plan.add_argument("--limit", type=int, default=100, help="Maximum findings to include.")
    p_plan.add_argument("--output-json", help="Optional file path to export plan JSON.")
    p_plan.set_defaults(func=cmd_plan)

    # 3. apply
    p_apply = subparsers.add_parser("apply", help="Execute explicit controlled apply of reconciliation plan.")
    p_apply.add_argument("--plan-id", required=True, help="Reconciliation plan identifier.")
    p_apply.add_argument("--actor", help="Operator actor name executing apply.")
    p_apply.add_argument("--max-actions", type=int, default=100, help="Maximum actions to execute in this batch.")
    p_apply.set_defaults(func=cmd_apply)

    # 4. grant
    p_grant = subparsers.add_parser("grant", help="Perform audited manual entitlement grant.")
    p_grant.add_argument("--actor", required=True, help="Operator/staff identifier.")
    p_grant.add_argument("--user", required=True, help="Target user ID.")
    p_grant.add_argument("--benefit", required=True, help="Catalog dot-notated benefit ID.")
    p_grant.add_argument("--valid-days", type=int, help="Validity duration in days.")
    p_grant.add_argument("--valid-until", help="Explicit ISO 8601 expiration timestamp.")
    p_grant.add_argument("--reason", required=True, help="Business justification.")
    p_grant.add_argument("--ticket", required=True, help="Support/incident ticket identifier.")
    p_grant.add_argument("--idempotency-key", required=True, help="Unique operator idempotency key.")
    p_grant.set_defaults(func=cmd_grant)

    # 5. revoke
    p_revoke = subparsers.add_parser("revoke", help="Perform audited manual entitlement revocation.")
    p_revoke.add_argument("--actor", required=True, help="Operator/staff identifier.")
    p_revoke.add_argument("--grant-id", required=True, help="Target grant ID to revoke.")
    p_revoke.add_argument("--reason", required=True, help="Business justification.")
    p_revoke.add_argument("--ticket", required=True, help="Support/incident ticket identifier.")
    p_revoke.add_argument("--idempotency-key", required=True, help="Unique operator idempotency key.")
    p_revoke.set_defaults(func=cmd_revoke)

    # 6. audit
    p_audit = subparsers.add_parser("audit", help="Inspect manual grant audit history.")
    p_audit.add_argument("--user", help="Filter by target user ID.")
    p_audit.add_argument("--actor", help="Filter by operator actor.")
    p_audit.add_argument("--limit", type=int, default=50, help="Maximum records to display.")
    p_audit.set_defaults(func=cmd_audit)

    # 7. recover-audits
    p_rec = subparsers.add_parser("recover-audits", help="Recover in-flight/interrupted audit records.")
    p_rec.add_argument("--min-age", type=int, default=60, help="Minimum age in seconds before considering in-flight audits stalled (default: 60).")
    p_rec.set_defaults(func=cmd_recover_audits)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

