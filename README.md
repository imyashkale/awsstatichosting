# terraform-aws-static-hosting

Reusable Terraform module that provisions a production-ready AWS static website stack. Works with any framework that produces a static build output — React, Vue, Next.js (export), Angular, Astro, plain HTML, etc.

```
S3 (private origin) → CloudFront (CDN + OAC) → Route53 (DNS) + ACM (TLS)
```

---

## Architecture

```
    User Browser
        │
        │  HTTPS request: example.com/about
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│                        Route53                                │
│                                                               │
│  Hosted zone: example.com                                     │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  A    record  →  ALIAS to CloudFront distribution    │     │
│  │  AAAA record  →  ALIAS to CloudFront distribution    │     │
│  │  CNAME records →  ACM DNS validation (auto-managed)  │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                               │
│  Route53 resolves example.com to the nearest CloudFront       │
│  edge location using anycast routing.                         │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                     CloudFront (CDN)                          │
│                                                               │
│  Distribution Settings:                                       │
│  ├── HTTPS enforced (viewer-protocol: redirect-to-https)      │
│  ├── TLS 1.2 minimum (TLSv1.2_2021) via ACM certificate      │
│  ├── IPv4 + IPv6 enabled                                      │
│  ├── Gzip/Brotli compression enabled                          │
│  └── Managed-CachingOptimized cache policy                    │
│                                                               │
│  Optional Features:                                           │
│  ├── URL Rewrite Function (enable_url_rewrite_function)       │
│  │   Runs at viewer-request phase:                            │
│  │     /about     → /about/index.html                         │
│  │     /about/    → /about/index.html                         │
│  │     /style.css → /style.css  (unchanged, has extension)    │
│  │                                                            │
│  ├── SPA Error Handling (spa_mode)                            │
│  │   403 → 200 /index.html                                    │
│  │   404 → 200 /index.html                                    │
│  │   Lets client-side router (React Router, Vue Router)       │
│  │   handle all routes.                                       │
│  │                                                            │
│  └── Access Logging (enable_cf_logging)                       │
│      Every request logged to a dedicated S3 bucket:           │
│        Client IP, User-Agent, URI, timestamp, bytes served    │
│      Logs arrive within ~5–10 minutes. Query with Athena      │
│      or download for grep/analysis.                           │
│                                                               │
│  Origin Access Control (OAC):                                 │
│  Every request to S3 is signed with SigV4. No direct          │
│  public access to the bucket is possible.                     │
└──────────────────────┬───────────────────────────────────────┘
                       │  SigV4-signed request
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                     S3 Bucket (Private)                        │
│                                                               │
│  Security:                                                    │
│  ├── All public access blocked (4 flags)                      │
│  ├── Bucket policy allows ONLY cloudfront.amazonaws.com       │
│  │   with condition: AWS:SourceArn = this distribution's ARN  │
│  └── AES-256 server-side encryption with bucket key           │
│                                                               │
│  Durability:                                                  │
│  └── Versioning enabled (rollback capable)                    │
│                                                               │
│  Naming:                                                      │
│  └── {domain-with-dashes}-{environment}-website               │
│      e.g. example-com-prod-website                            │
└──────────────────────────────────────────────────────────────┘

                    ┌──────────────────────┐
                    │    ACM (us-east-1)    │
                    │                      │
                    │  Certificate for:    │
                    │  • example.com       │
                    │  • www.example.com   │
                    │                      │
                    │  Validation: DNS     │
                    │  (auto via Route53)  │
                    └──────────────────────┘
```

### How the pieces connect

1. **S3** stores your static build files (`index.html`, JS bundles, CSS, images). The bucket is completely private — no public access at all.

2. **CloudFront** sits in front of S3 as a CDN. It uses **Origin Access Control (OAC)** to sign every request to S3 with SigV4 credentials. This is the modern replacement for the older OAI (Origin Access Identity) approach. Responses are cached at 450+ edge locations worldwide.

3. **ACM** provisions a free TLS certificate for your domain (and `www.` subdomain). The certificate **must** be in `us-east-1` — this is an AWS requirement for CloudFront. DNS validation records are created automatically in Route53.

4. **Route53** serves two purposes:
   - Creates CNAME records for ACM certificate DNS validation (always created)
   - Creates A and AAAA alias records pointing your domain to CloudFront (only when `enable_custom_domain = true`)

### Terraform resource dependency order

```
Step 1  │  S3 bucket created
Step 2  │  ACM certificate requested in us-east-1          (parallel with step 1)
Step 3  │  Route53 CNAME records for ACM DNS validation     (needs ACM validation options)
Step 4  │  ACM certificate validation waits for DNS         (needs Route53 records, ~2-5 min)
Step 5  │  CloudFront distribution created                  (needs S3 bucket + validated cert)
Step 6  │  S3 bucket policy applied                         (needs CloudFront distribution ARN)
Step 7  │  Route53 A/AAAA alias records created             (needs CloudFront domain name)
```

> ACM DNS validation typically takes 2-5 minutes. Terraform blocks at step 4 until AWS confirms the certificate status is `ISSUED`.

---

## Usage

```hcl
module "static_site" {
  source = "git::https://github.com/<your-org>/awshosting.git?ref=v1.0.0"

  project_name = "portfolio"
  environment  = "prod"
  domain_name  = "example.com"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

The calling root module **must** define two AWS provider configurations:

```hcl
provider "aws" {
  region = "ap-southeast-2"  # your preferred region
}

# Required — ACM certificates for CloudFront must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

### React app example

```hcl
module "react_app" {
  source = "git::https://github.com/<your-org>/awshosting.git?ref=v1.0.0"

  project_name = "my-react-app"
  environment  = "prod"
  domain_name  = "app.example.com"

  spa_mode                    = true   # React Router handles all routes
  enable_url_rewrite_function = false  # not needed — SPA mode covers routing

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

### Static site / SSG example (Astro, Hugo, Next.js export)

```hcl
module "docs_site" {
  source = "git::https://github.com/<your-org>/awshosting.git?ref=v1.0.0"

  project_name = "docs"
  environment  = "prod"
  domain_name  = "docs.example.com"

  spa_mode                    = false  # no client-side router
  enable_url_rewrite_function = true   # /guides/setup → /guides/setup/index.html

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

---

## Prerequisites

- Terraform `>= 1.5.0`
- AWS credentials with permissions for: S3, CloudFront, ACM, Route53, IAM
- A **Route53 hosted zone** must already exist for the `domain_name`

---

## Inputs

### Required

| Variable | Type | Description |
|---|---|---|
| `project_name` | `string` | Project name used as a prefix for all resource names. Combined with `environment` to create unique identifiers (e.g. OAC name: `{project_name}-{environment}-oac`, CloudFront Function: `{project_name}-{environment}-url-rewrite`). |
| `environment` | `string` | Environment name such as `dev`, `staging`, or `prod`. Used in resource naming and added as an `Environment` tag on all resources. Also used in the S3 bucket name: `{domain-dashed}-{environment}-website`. |
| `domain_name` | `string` | The custom domain for the website (e.g. `example.com`). A Route53 public hosted zone must already exist for this domain. The ACM certificate will cover both `example.com` and `www.example.com`. The S3 bucket name is derived from this value by replacing dots with dashes. |

### Optional

| Variable | Type | Default | Description |
|---|---|---|---|
| `enable_custom_domain` | `bool` | `true` | Controls whether the CloudFront distribution gets the custom domain alias and whether Route53 A/AAAA alias records are created. When `false`, the site is accessible only via the auto-generated `*.cloudfront.net` URL. The ACM certificate and its DNS validation records are always created regardless of this setting. |
| `default_root_object` | `string` | `"index.html"` | The object CloudFront returns when the viewer requests the root URL (`/`). For most frameworks this is `index.html`. This only applies to the root path — subdirectory rewrites are handled by the URL rewrite function if enabled. |
| `price_class` | `string` | `"PriceClass_100"` | Determines which CloudFront edge locations serve your content. Affects both performance (latency) and cost. Options: `PriceClass_100` — North America + Europe (cheapest). `PriceClass_200` — adds Asia, Middle East, Africa. `PriceClass_All` — all 450+ edge locations globally (most expensive). |
| `spa_mode` | `bool` | `true` | When enabled, CloudFront returns `/index.html` with a `200` status for both `403` and `404` errors from S3. This allows client-side routers (React Router, Vue Router, Angular Router) to handle all URL paths. The error response is cached for 10 seconds. Set to `false` for static-site generators where every route has a corresponding file in S3. |
| `enable_url_rewrite_function` | `bool` | `true` | When enabled, creates and attaches a CloudFront Function that runs on every viewer request. The function rewrites directory-style URIs to their `index.html` equivalent: `/about` becomes `/about/index.html`, `/about/` becomes `/about/index.html`. URIs with a file extension (e.g. `/style.css`, `/app.js`) are left unchanged. When disabled, no CloudFront Function resource is created at all — nothing is attached to the distribution. Disable this for pure SPA apps where `spa_mode` alone handles routing. |
| `enable_cf_logging` | `bool` | `false` | When enabled, creates a dedicated S3 bucket (`{domain-dashed}-{env}-cf-logs`) and turns on CloudFront access logging. Every request is logged with client IP, User-Agent, URI, timestamp, HTTP status, and bytes served. Logs land in S3 within ~5–10 minutes under the prefix `{domain_name}/`. Use Athena or download and grep for specific time windows. The log bucket uses `BucketOwnerPreferred` ownership so CloudFront's ACL-based writes are accessible to your account. |

### Choosing `spa_mode` vs `enable_url_rewrite_function`

| App Type | `spa_mode` | `enable_url_rewrite_function` | Why |
|---|---|---|---|
| React / Vue / Angular SPA | `true` | `false` | All routes are handled by the client-side router. The 403/404 rewrite to `index.html` is all you need. |
| Static site generator (Hugo, Jekyll, Astro) | `false` | `true` | Every route has a real file in S3. The URL rewrite function maps clean URLs to the correct `index.html` file in each directory. |
| Next.js / Nuxt static export | `true` | `true` | Hybrid — most routes have real files, but fallback to the SPA shell for dynamic routes. |
| Plain HTML site | `false` | `false` | Direct file serving, no rewrites needed. |

---

## Outputs

| Output | Description | Example Value | Common Use |
|---|---|---|---|
| `website_url` | The public HTTPS URL of the website. Returns the custom domain URL when `enable_custom_domain = true`, otherwise returns the CloudFront `*.cloudfront.net` URL. | `https://example.com` | Link to the live site. |
| `s3_bucket_name` | The name of the S3 bucket that holds the website files. This is the target for `aws s3 sync` deployments. | `example-com-prod-website` | Deploy: `aws s3 sync ./dist s3://{s3_bucket_name} --delete` |
| `s3_bucket_arn` | The ARN of the S3 bucket. | `arn:aws:s3:::example-com-prod-website` | IAM policies, cross-account access, CI/CD permissions. |
| `cloudfront_distribution_id` | The CloudFront distribution ID. Required for cache invalidations after deploying new content. | `E1A2B3C4D5E6F7` | Invalidate: `aws cloudfront create-invalidation --distribution-id {id} --paths "/*"` |
| `cloudfront_distribution_arn` | The full ARN of the CloudFront distribution. | `arn:aws:cloudfront::123456789012:distribution/E1A2B3C4D5E6F7` | IAM policies, AWS WAF association, resource tagging. |
| `cloudfront_distribution_domain_name` | The auto-assigned `*.cloudfront.net` domain name. Available regardless of custom domain settings. | `d1234abcdef8.cloudfront.net` | Testing before DNS cutover, CNAME targets for external DNS. |
| `acm_certificate_arn` | The ARN of the ACM TLS certificate in `us-east-1`. Covers both `example.com` and `www.example.com`. | `arn:aws:acm:us-east-1:123456789012:certificate/abc-123` | Reference for other resources that need the same cert. |
| `route53_zone_id` | The Route53 hosted zone ID for the domain. | `Z0123456789ABCDEFGHIJ` | Creating additional DNS records in the same zone. |

---

## Post-Deploy Commands

**Upload build output to S3:**
```bash
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket_name) --delete
```

**Invalidate CloudFront cache after deploy:**
```bash
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

**Full deploy (sync + invalidate):**
```bash
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket_name) --delete && \
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

---

## Project Structure

```
.
├── main.tf              # All resources — S3, CloudFront, ACM, Route53
├── variables.tf         # Module input interface (8 variables)
├── outputs.tf           # Module outputs (8 values)
├── versions.tf          # required_providers with configuration_aliases
├── locals.tf            # Derived values (bucket name, origin ID)
├── functions/
│   └── url-rewrite.js   # CloudFront Function: directory URI → index.html
└── examples/
    └── complete/        # Full working example showing module consumption
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── providers.tf
        └── terraform.tfvars
```

---

## AWS Resources Created

| Resource | Name Pattern | Conditional |
|---|---|---|
| `aws_s3_bucket` | `{domain-dashed}-{env}-website` | Always |
| `aws_s3_bucket_versioning` | — | Always |
| `aws_s3_bucket_server_side_encryption_configuration` | — | Always |
| `aws_s3_bucket_public_access_block` | — | Always |
| `aws_s3_bucket_policy` | — | Always |
| `aws_acm_certificate` | `{domain_name}` + `www.{domain_name}` | Always |
| `aws_acm_certificate_validation` | — | Always |
| `aws_route53_record.acm_validation` | CNAME records for DNS validation | Always |
| `aws_route53_record.website_a` | A alias → CloudFront | `enable_custom_domain` |
| `aws_route53_record.website_aaaa` | AAAA alias → CloudFront | `enable_custom_domain` |
| `aws_cloudfront_origin_access_control` | `{project}-{env}-oac` | Always |
| `aws_cloudfront_distribution` | `{project}-{env} static website` | Always |
| `aws_cloudfront_function` | `{project}-{env}-url-rewrite` | `enable_url_rewrite_function` |
| `aws_s3_bucket` (logs) | `{domain-dashed}-{env}-cf-logs` | `enable_cf_logging` |
| `aws_s3_bucket_ownership_controls` (logs) | — | `enable_cf_logging` |
