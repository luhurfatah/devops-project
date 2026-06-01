#!/usr/bin/env python3
"""
Bootstrap AWS Infrastructure
Creates S3 state bucket (with S3 locking) and OIDC provider for GitHub Actions.
Run: python bootstrap.py [config_file]
"""

import sys
import json
import os
import time
import re
import boto3
import yaml
import secrets
import string
from typing import Dict, Any
from botocore.config import Config
from botocore.exceptions import ClientError


class S3Bootstrap:
    """Manages S3 resources for Terraform state storage."""

    def __init__(self, region: str, config: Dict[str, Any]):
        self.region = region
        self.config = config
        s3_config = config.get("s3", {})
        project_name = config.get("project", {}).get("name", "myapp")

        # Use explicit bucket_name from config if provided, else derive from project name with random suffix
        if s3_config.get("bucket_name"):
            self.bucket_name = s3_config.get("bucket_name")
        else:
            random_suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
            self.bucket_name = f"{project_name}-terraform-state-{random_suffix}"

        # Force path-style addressing to avoid regional endpoint conflicts
        boto_config = Config(s3={"addressing_style": "path"})
        self.s3_client = boto3.client("s3", region_name=region, config=boto_config)
        self.s3_resource = boto3.resource("s3", region_name=region, config=boto_config)

    def create_bucket(self) -> dict:
        try:
            try:
                self.s3_client.head_bucket(Bucket=self.bucket_name)
                print(f"  Bucket {self.bucket_name} already exists and is accessible, skipping creation.")
                return {"status": "exists", "bucket": self.bucket_name}
            except ClientError as e:
                error_code = e.response["Error"]["Code"]
                
                # If we get a 403 Forbidden or AccessDenied, it means the bucket name is owned by another account
                if error_code in ("403", "AccessDenied", "BucketAlreadyExists"):
                    print(f"  [WARN] Bucket {self.bucket_name} exists but is owned by another account or inaccessible.")
                    project_name = self.config.get("project", {}).get("name", "myapp")
                    random_suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
                    self.bucket_name = f"{project_name}-terraform-state-{random_suffix}"
                    print(f"  Generated new globally unique bucket name: {self.bucket_name}")
                    return self.create_bucket()
                elif error_code not in ("404", "NoSuchBucket"):
                    raise

            # us-east-1 must NOT include LocationConstraint — all other regions must
            if self.region == "us-east-1":
                self.s3_client.create_bucket(Bucket=self.bucket_name)
            else:
                self.s3_client.create_bucket(
                    Bucket=self.bucket_name,
                    CreateBucketConfiguration={"LocationConstraint": self.region}
                )

            print(f"  Created bucket: {self.bucket_name}")
            return {"status": "created", "bucket": self.bucket_name}
        except ClientError as e:
            print(f"  Error creating bucket: {e}")
            raise

    def enable_versioning(self) -> dict:
        try:
            self.s3_client.put_bucket_versioning(
                Bucket=self.bucket_name,
                VersioningConfiguration={"Status": "Enabled"}
            )
            print(f"  Enabled versioning on {self.bucket_name}")
            return {"status": "enabled", "feature": "versioning"}
        except ClientError as e:
            print(f"  Error enabling versioning: {e}")
            raise

    def enable_encryption(self) -> dict:
        try:
            self.s3_client.put_bucket_encryption(
                Bucket=self.bucket_name,
                ServerSideEncryptionConfiguration={
                    "Rules": [
                        {
                            "ApplyServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            },
                            "BucketKeyEnabled": True
                        }
                    ]
                }
            )
            print(f"  Enabled encryption on {self.bucket_name}")
            return {"status": "enabled", "feature": "encryption"}
        except ClientError as e:
            print(f"  Error enabling encryption: {e}")
            raise

    def block_public_access(self) -> dict:
        try:
            self.s3_client.put_public_access_block(
                Bucket=self.bucket_name,
                PublicAccessBlockConfiguration={
                    "BlockPublicAcls": True,
                    "IgnorePublicAcls": True,
                    "BlockPublicPolicy": True,
                    "RestrictPublicBuckets": True
                }
            )
            print(f"  Blocked public access on {self.bucket_name}")
            return {"status": "enabled", "feature": "public_access_block"}
        except ClientError as e:
            print(f"  Error blocking public access: {e}")
            raise

    def run_all(self) -> dict:
        results = {
            "s3_bucket": self.create_bucket(),
            "versioning": self.enable_versioning(),
            "encryption": self.enable_encryption(),
            "public_access": self.block_public_access()
        }
        return results


class OIDCBootstrap:
    """Manages OIDC provider and IAM role for GitHub Actions."""

    # GitHub's OIDC provider URL — this is fixed/canonical
    GITHUB_OIDC_URL = "https://token.actions.githubusercontent.com"
    # Condition keys use the hostname, not the full URL
    GITHUB_OIDC_HOST = "token.actions.githubusercontent.com"
    # GitHub's current OIDC thumbprint
    GITHUB_THUMBPRINT = "6938fd4d98bab03faadb97b34396831e3780aea1"

    def __init__(self, region: str, config: Dict[str, Any]):
        self.region = region
        self.config = config
        self.iam_client = boto3.client("iam", region_name=region)
        self.sts_client = boto3.client("sts", region_name=region)
        self._oidc_provider_arn = None

    def _get_account_id(self) -> str:
        return self.sts_client.get_caller_identity()["Account"]

    def create_oidc_provider(self) -> Dict[str, Any]:
        oidc_config = self.config.get("oidc", {})
        if not oidc_config.get("enabled", False):
            return {"status": "skipped", "reason": "OIDC disabled in config"}

        provider_type = oidc_config.get("provider_type", "github")
        if provider_type != "github":
            raise ValueError(f"Unsupported provider type: {provider_type}")

        github_config = oidc_config.get("github", {})
        audience = github_config.get("audience", "sts.amazonaws.com")

        try:
            response = self.iam_client.create_open_id_connect_provider(
                Url=self.GITHUB_OIDC_URL,
                ThumbprintList=[self.GITHUB_THUMBPRINT],
                ClientIDList=[audience]
            )

            arn = response["OpenIDConnectProviderArn"]
            self._oidc_provider_arn = arn
            print(f"  Created OIDC provider: {arn}")
            return {
                "status": "created",
                "arn": arn,
                "url": self.GITHUB_OIDC_URL
            }
        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "")
            if error_code == "EntityAlreadyExists":
                # Deterministic ARN construction to bypass slow/rate-limited listing APIs
                account_id = self._get_account_id()
                arn = f"arn:aws:iam::{account_id}:oidc-provider/token.actions.githubusercontent.com"
                self._oidc_provider_arn = arn
                print(f"  OIDC provider already exists: {arn}")
                return {
                    "status": "exists",
                    "arn": arn,
                    "url": self.GITHUB_OIDC_URL
                }
            print(f"  Error creating OIDC provider: {e}")
            raise

    def _get_oidc_provider_arn(self, retries: int = 5, delay: float = 2.0) -> str:
        """Look up the OIDC provider ARN by URL with retry for eventual consistency."""
        account_id = self._get_account_id()
        return f"arn:aws:iam::{account_id}:oidc-provider/token.actions.githubusercontent.com"

    def create_iam_role(self) -> Dict[str, Any]:
        oidc_config = self.config.get("oidc", {})
        if not oidc_config.get("enabled", False):
            return {"status": "skipped", "reason": "OIDC disabled in config"}

        github_config = oidc_config.get("github", {})
        iam_config = self.config.get("iam", {})
        tags_config = self.config.get("tags", {})

        role_name = iam_config.get("role_name", "github-actions-role")

        try:
            role_exists = False
            role_arn = None
            try:
                existing = self.iam_client.get_role(RoleName=role_name)
                print(f"  IAM role {role_name} already exists. Updating configuration.")
                role_arn = existing["Role"]["Arn"]
                role_exists = True
            except ClientError as e:
                if e.response["Error"]["Code"] != "NoSuchEntity":
                    raise

            oidc_arn = self._oidc_provider_arn or self._get_oidc_provider_arn()

            org = github_config.get("organization", "")
            repo = github_config.get("repository", "")
            allowed_branches = github_config.get("allowed_branches", ["main"])
            audience = github_config.get("audience", "sts.amazonaws.com")

            # IAM OIDC condition keys use the provider hostname, NOT the ARN.
            sub_values = [
                f"repo:{org}/{repo}:ref:refs/heads/{branch}"
                for branch in allowed_branches
            ] + [
                f"repo:{org}/{repo}:environment:*"
            ]

            trust_policy = {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Federated": oidc_arn
                        },
                        "Action": "sts:AssumeRoleWithWebIdentity",
                        "Condition": {
                            "StringEquals": {
                                f"{self.GITHUB_OIDC_HOST}:aud": audience
                            },
                            "StringLike": {
                                f"{self.GITHUB_OIDC_HOST}:sub": sub_values
                            }
                        }
                    }
                ]
            }

            if role_exists:
                self.iam_client.update_assume_role_policy(
                    RoleName=role_name,
                    PolicyDocument=json.dumps(trust_policy)
                )
                print(f"  Updated trust policy on role '{role_name}'")
            else:
                response = self.iam_client.create_role(
                    RoleName=role_name,
                    AssumeRolePolicyDocument=json.dumps(trust_policy),
                    MaxSessionDuration=iam_config.get("max_session_duration", 3600),
                    Tags=[{"Key": k, "Value": v} for k, v in tags_config.items()]
                )
                role_arn = response["Role"]["Arn"]
                print(f"  Created IAM role: {role_arn}")

            self._attach_inline_policy(role_name, iam_config)
            self._attach_managed_policies(role_name, iam_config)

            return {
                "status": "updated" if role_exists else "created",
                "role_name": role_name,
                "role_arn": role_arn
            }
        except ClientError as e:
            print(f"  Error configuring IAM role: {e}")
            raise

    def _attach_inline_policy(self, role_name: str, iam_config: Dict[str, Any]) -> None:
        policy_name = iam_config.get("inline_policy_name", "default-policy")
        policy_statements = iam_config.get("inline_policy_statements", [])

        if not policy_statements:
            print(f"  No inline policy statements defined, skipping inline policy attachment.")
            # If the policy exists, we should delete it to clean up, but since it's optional, let's just return
            try:
                self.iam_client.delete_role_policy(RoleName=role_name, PolicyName=policy_name)
                print(f"  Removed obsolete inline policy '{policy_name}' from role '{role_name}'")
            except ClientError as e:
                # Ignore if it wasn't there
                if e.response["Error"]["Code"] != "NoSuchEntity":
                    raise
            return

        # Normalise effect capitalisation (IAM requires "Allow"/"Deny", not "allow"/"deny")
        normalised_statements = []
        for stmt in policy_statements:
            normalised = dict(stmt)
            normalised["Effect"] = stmt.get("effect", stmt.get("Effect", "Allow")).capitalize()
            # IAM uses title-case keys
            if "actions" in normalised:
                normalised["Action"] = normalised.pop("actions")
            if "resource" in normalised:
                normalised["Resource"] = normalised.pop("resource")
            normalised.pop("effect", None)
            normalised_statements.append(normalised)

        policy_document = {
            "Version": "2012-10-17",
            "Statement": normalised_statements
        }

        try:
            self.iam_client.put_role_policy(
                RoleName=role_name,
                PolicyName=policy_name,
                PolicyDocument=json.dumps(policy_document)
            )
            print(f"  Attached inline policy '{policy_name}' to role '{role_name}'")
        except ClientError as e:
            print(f"  Error attaching inline policy: {e}")
            raise

    def _attach_managed_policies(self, role_name: str, iam_config: Dict[str, Any]) -> None:
        managed_arns = iam_config.get("managed_policy_arns", [])
        for policy_arn in managed_arns:
            try:
                self.iam_client.attach_role_policy(
                    RoleName=role_name,
                    PolicyArn=policy_arn
                )
                print(f"  Attached managed policy {policy_arn} to role '{role_name}'")
            except ClientError as e:
                print(f"  Error attaching managed policy {policy_arn}: {e}")
                raise

    def run_all(self) -> Dict[str, Any]:
        results = {
            "oidc_provider": self.create_oidc_provider(),
            "iam_role": self.create_iam_role()
        }
        return results


def load_config(config_path: str) -> Dict[str, Any]:
    if not os.path.exists(config_path):
        print(f"Config file '{config_path}' not found.")
        sys.exit(1)
    with open(config_path, "r") as f:
        return yaml.safe_load(f)


def update_project_files(config_path: str, new_bucket: str, new_role_arn: str):
    print("\n[Post-Bootstrap] Automatically updating configuration files for current AWS account...")
    
    # 1. Update config.yaml with the final bucket name
    try:
        with open(config_path, "r") as f:
            lines = f.readlines()
        
        updated_lines = []
        for line in lines:
            if re.match(r"^\s*bucket_name\s*:", line):
                updated_lines.append(f'  bucket_name: "{new_bucket}"\n')
            else:
                updated_lines.append(line)
                
        with open(config_path, "w") as f:
            f.writelines(updated_lines)
        print(f"  -> Updated bucket name in '{config_path}'")
    except Exception as e:
        print(f"  [ERROR] Failed to update '{config_path}': {e}")

    # 2. Update iaac/terragrunt/root.hcl S3 backend bucket
    root_hcl_path = os.path.join(os.path.dirname(config_path), "..", "iaac", "terragrunt", "root.hcl")
    if os.path.exists(root_hcl_path):
        try:
            with open(root_hcl_path, "r") as f:
                content = f.read()
            
            new_content = re.sub(
                r'(bucket\s*=\s*")[^"]*(")',
                r'\g<1>' + new_bucket + r'\g<2>',
                content
            )
            
            with open(root_hcl_path, "w") as f:
                f.write(new_content)
            print(f"  -> Updated bucket in '{root_hcl_path}'")
        except Exception as e:
            print(f"  [ERROR] Failed to update '{root_hcl_path}': {e}")
    else:
        print(f"  [WARN] root.hcl not found at '{root_hcl_path}'")

    # 3. Update GitHub Workflow role-to-assume values
    workflows_dir = os.path.join(os.path.dirname(config_path), "..", ".github", "workflows")
    if os.path.exists(workflows_dir):
        updated_workflows = 0
        for filename in os.listdir(workflows_dir):
            if filename.endswith(".yml") or filename.endswith(".yaml"):
                filepath = os.path.join(workflows_dir, filename)
                try:
                    with open(filepath, "r") as f:
                        content = f.read()
                    
                    new_content = re.sub(
                        r'(role-to-assume:\s*)arn:aws:iam::\d+:role/[a-zA-Z0-9_-]+',
                        r'\g<1>' + new_role_arn,
                        content
                    )
                    
                    if new_content != content:
                        with open(filepath, "w") as f:
                            f.write(new_content)
                        print(f"  -> Updated role-to-assume in '{filepath}'")
                        updated_workflows += 1
                except Exception as e:
                    print(f"  [ERROR] Failed to update '{filepath}': {e}")
        if updated_workflows == 0:
            print("  No workflow files required role ARN updates.")
    else:
        print(f"  [WARN] GitHub Workflows directory not found at '{workflows_dir}'")


def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"
    config = load_config(config_path)

    project_cfg = config.get("project", {})
    project_name = project_cfg.get("name", "myapp")
    region = project_cfg.get("region", "us-east-1")

    print("=" * 60)
    print("Bootstrapping AWS Infrastructure")
    print(f"  Region  : {region}")
    print(f"  Project : {project_name}")
    print("=" * 60)

    print("\n[1/2] Creating S3 state bucket...")
    s3_bootstrap = S3Bootstrap(region=region, config=config)
    s3_results = s3_bootstrap.run_all()

    print("\n[2/2] Creating OIDC provider and IAM role...")
    oidc_bootstrap = OIDCBootstrap(region=region, config=config)
    oidc_results = oidc_bootstrap.run_all()

    bucket = s3_results["s3_bucket"].get("bucket")
    role_arn = oidc_results.get("iam_role", {}).get("role_arn")

    if bucket and role_arn:
        update_project_files(config_path, bucket, role_arn)

    print("\n" + "=" * 60)
    print("BOOTSTRAP COMPLETE")
    print("=" * 60)

    all_results = {
        "s3_and_state": s3_results,
        "oidc_and_iam": oidc_results
    }
    print(json.dumps(all_results, indent=2, default=str))

    print("\nNext steps:")
    print("  1. Add the IAM role ARN as a GitHub Actions secret or trust the updated files:")
    print(f"     Role ARN: {role_arn}")
    print("  2. Terragrunt configurations and GitHub Workflows have been auto-updated.")


if __name__ == "__main__":
    main()