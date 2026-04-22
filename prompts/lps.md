

add pipeline and all its relevant skills and subagents:
The pipeline goal is to:
UI Design, Implement, deploy and host a one landing page on a domain using AWS cloud.
Sometimes the domain will exist so the pipeline will execute only the desig, implement, deploy.
 

1.create landing page design ui/ux (designer subagent)
2.implement static files (js, css,html) SKILLs: (landing page social)
3.using script: 
  create a subagent that (that uses only predefined scripts) who uploads files under /lpname to exisitng/new s3 public website bucket (aws-s3-provisioner)
  create a sh script that:
  a. creates a aws bucket if not exists
  b. remove public block and apply allow for public website with index.html (defsult+error) policy and settings
  c. sync all files in a dir to the bucket
  d. add logs
  e. try to fetch the website from the s3 website endpoint
  
  
  
4.create a subagent that (that uses only predefined scripts)
  the python script will: create distribution (view lambda, /lead behavior and func) + buy domain + acm+ route records (aws subagent script)
  assume that this script exists i will fill it later.



Each step is done by utilizing subagents and skills only, dont invent.
Check which skills are there and link them.

##AWS:
# Simplified Architecture

Yes.

You can simplify it to:

- keep **CloudFront**
- keep **Lambda@Edge**
- keep **S3**
- replace **API Gateway** with a **Lambda Function URL**
- replace **Secrets Manager** with **Lambda environment variables**

This is a valid production setup if you accept the tradeoffs. CloudFront can use a Lambda Function URL as an origin, and AWS recommends protecting that origin with **Origin Access Control (OAC)** when used behind CloudFront. Lambda environment variables are encrypted at rest by AWS Lambda, and you can use a customer-managed KMS key if needed.  [oai_citation:0‡AWS Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html?utm_source=chatgpt.com)

---

## New High-Level Diagram

```text
                        ┌──────────────────────────────┐
                        │           User               │
                        └──────────────┬───────────────┘
                                       │
                                       ▼
                        ┌──────────────────────────────┐
                        │        CloudFront            │
                        │  - TLS / custom domain       │
                        │  - path-based routing        │
                        └──────────────┬───────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    │ viewer-request                      │ path: /lead
                    ▼                                     ▼
        ┌───────────────────────────┐        ┌───────────────────────────┐
        │      Lambda@Edge          │        │    Lambda Function URL    │
        │  - blocklist logic        │        │      (lead handler)       │
        │  - UA regex match         │        │   behind CloudFront OAC   │
        │  - IP regex match         │        └──────────────┬────────────┘
        │  - rewrite URI            │                       │
        └──────────────┬────────────┘                       ▼
                       │                      ┌───────────────────────────┐
                       ▼                      │       Lead Lambda         │
        ┌───────────────────────────┐         │  - validate payload       │
        │          S3 Bucket        │         │  - connect to MongoDB     │
        │  /hello/index.html        │         │  - persist lead           │
        │  /blocked/index.html      │         └──────────────┬────────────┘
        │  static assets            │                        │
        └───────────────────────────┘                        ▼
                                              ┌───────────────────────────┐
                                              │         MongoDB           │
                                              │      Atlas / managed      │
                                              └───────────────────────────┘