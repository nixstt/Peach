# Lab Notes & Class Discussion

## 1. Stretch Goal: API Protection

### Why does verification happen in the backend? What could an attacker do if only the frontend checked whether the user is signed in?
Frontend code runs entirely in the user's browser. An attacker has unrestricted access to the browser's JavaScript environment, network tab, and memory. If only the frontend checked authentication:
- An attacker could open terminal / `curl` or Postman and make direct HTTP requests (`GET`, `POST`) straight to the API endpoint (`https://7eaqqj55z1.execute-api.eu-north-1.amazonaws.com/api/meetings`), completely bypassing the frontend UI.
- They could read, alter, or delete all records without having valid credentials.
The backend is the trusted boundary; it must independently verify the digital signature, issuer, expiration, and audience/client ID of the token before executing any database queries or mutations.

### Why not `AuthType: AWS_IAM` on the function URL?
- `AuthType: AWS_IAM` requires incoming HTTP requests to be signed using **AWS Signature Version 4 (SigV4)** using AWS IAM credentials (`AccessKeyId`, `SecretAccessKey`, `SessionToken`).
- Standard web/mobile users logging in via Google or Cognito email/password receive standard OIDC/OAuth 2.0 JWTs (ID and Access tokens).
- Translating OIDC JWTs into IAM SigV4 signatures would require deploying a Cognito Identity Pool (Federated Identities) to exchange JWTs for temporary STS credentials in the browser, adding significant architectural complexity, latency, and extra STS API calls for every request.

### What would a JWT authorizer on API Gateway take off your code, and what would it add to your bill?
- **Off your code:** It eliminates the need for manual JWT decoding, cryptographic signature validation (`RS256`), issuer checks, and JWKS caching logic inside the FastAPI application (`backend/app/auth.py`). Unauthorized or expired requests are rejected at the AWS edge before ever reaching ECS/Lambda compute.
- **To your bill:** With HTTP APIs, requests that fail authorization are still billed as API Gateway requests (\$1.00 per million requests). For REST APIs (v1), custom Lambda authorizers incur additional Lambda invocation and execution duration charges.

---

## 2. The Migration

### List every resource that bills by the hour in Stage 0. For each one, say what Stage 2 replaced it with, or why it simply disappeared.
1. **Application Load Balancer (ALB):** Billed at \~\$0.0225/hour base + LCU fees. In Stage 2, replaced by **Lambda Function URL** (frontend) and **API Gateway HTTP API** (backend), which have zero idle cost and bill purely per request.
2. **Public IPv4 Addresses:** Billed at \$0.005/hour per IP (\~\$3.60/month per IP). Disappeared because serverless resources (Lambda, API Gateway) share AWS-managed edge infrastructure, absorbing IP overhead into request pricing.
3. **Fargate Tasks (ECS):** Billed per vCPU-hour and GB-hour continuously even when idle. Replaced by **AWS Lambda**, which scales to zero when no traffic is received.
4. **RDS PostgreSQL (db.t4g.micro):** Billed 24/7 for instance hours and allocated EBS storage. Replaced by serverless compute/database scaling down during inactivity.
5. **NAT Gateway:** Billed at \~\$0.045/hour + \$0.045/GB data processed. Disappeared because Lambda/containers execute with direct public egress or serverless service integration without dedicated VPC NAT instances.

### The ALB and the public IPv4 addresses cost more than the code. What exactly are you paying for when you pay for them?
- **ALB:** You are paying for dedicated, managed compute instances provisioned by AWS across multiple Availability Zones that maintain high availability, TCP/TLS termination, health checks, and connection draining 24/7 regardless of traffic.
- **Public IPv4:** You are paying for the economic scarcity of the global 32-bit IPv4 address space. AWS charges \$0.005/hour per allocated address to encourage migration to IPv6 and recover IP acquisition costs.

### Aurora resumes in about 15 seconds. Who pays that cost, the company or a user? When is that acceptable, and when is it a bug?
- **Who pays:** The first user whose request initiates the database resume from zero ACU pays the penalty in the form of a 15-second latency delay.
- **When acceptable:** For internal admin dashboards, staging/testing environments, or low-frequency batch processes where long idle periods save substantial hosting fees.
- **When it is a bug:** For customer-facing production applications, public checkout flows, or SLAs requiring sub-second response times, where a 15-second freeze results in client timeouts, perceived downtime, and user churn.

### Stage 0 needed no CORS. Stage 2 does. What changed about origins, and what would you have to change to get back to a single origin?
- **What changed:** In Stage 0, both the static assets and the API were served behind the same ALB hostname (same protocol, host, and port). In Stage 2, the frontend is on a Lambda Function URL (`https://*.lambda-url.eu-north-1.on.aws`) while the backend API is on API Gateway (`https://*.execute-api.eu-north-1.amazonaws.com`). Browsers enforce the Same-Origin Policy, necessitating CORS headers.
- **To get back to a single origin:** Place both services behind a single **CloudFront distribution** or custom reverse proxy domain, routing `/api/*` to API Gateway and `/*` to S3 / Lambda Function URL.

### The frontend needs the API's URL at build time, and the API needs the frontend's URL for CORS. How does the Makefile break this cycle? Where else in this lab does the same cycle appear?
- **How Makefile breaks the cycle:** It deploys the backend stack first with a default/permissive origin to establish the `ApiUrl`. The frontend then builds against this `ApiUrl`. Finally, `deploy-frontend.sh` updates the backend's `CorsOrigins` parameter with the exact deployed frontend origin.
- **Where else it appears:** In Cognito OAuth callback/logout URLs. Cognito requires the frontend's callback URL before user pool creation, while the frontend requires the user pool ID and client ID to build its OIDC bundle. The auth stack deploys first, and then the frontend builds with the auth stack outputs.

### Why does the Lambda function have no NAT gateway? What stops working the day it needs to call an external API, such as an LLM provider?
- A Lambda function outside a VPC runs in AWS's default multi-tenant network with outbound internet routing.
- If the Lambda is attached to a private VPC subnet (to access private databases without public IPs), it immediately loses direct internet access. Without a NAT Gateway or VPC Endpoint, outbound connections to external third-party APIs (such as OpenAI or Anthropic) will hang and time out.

### Moving to us-east-1 simplified the deploy. What did it cost users in Ukraine, and what would it cost a company with EU customers?
- **Latency cost:** Physical distance causes network round-trip latency of 120–150 ms to `us-east-1` versus 30–45 ms to `eu-north-1` (Stockholm) or `eu-central-1` (Frankfurt).
- **Compliance / Regulatory cost:** Storing and processing European users' personal data (emails, names, logs) in the US without compliant transfer mechanisms (EU-US Data Privacy Framework or SCCs) violates GDPR data residency principles, risking fines up to €20M or 4% of annual global turnover.

---

## 3. The Cost

### Fill in the scenario table for your Lab 2 deployment. Which row are you in?
- **Row:** Serverless Scale-to-Zero / Low Traffic Tier.
- With zero requests, compute cost drops to \$0.00; storage and data transfer incur only negligible pennies.

### Your uptime monitor pings `/health` every minute. Does `/health` touch the database? If it does, what does the monitor cost you per month, and how would you fix it without losing the monitor?
- **Impact:** Pinging the database every 60 seconds prevents Aurora Serverless from ever idling down to 0 ACU, forcing it to run continuously 24/7 (720 hours/month at 0.5 ACU = \~\$43.20/month).
- **Fix:** Make `/health` a shallow check that returns `{"status": "ok"}` from process memory without querying PostgreSQL. Create a separate protected endpoint (`/health/db`) for on-demand deep diagnostics.

### At what traffic level would you migrate back to containers and an RDS instance? What would you watch in Cost Explorer to know you had reached it?
- **Traffic level:** When continuous traffic exceeds \~5–10 million monthly requests with sustained concurrency, where variable per-request and GB-second serverless fees exceed the fixed monthly cost of dedicated instances (\~\$35–\$45/month for a `t4g.micro` RDS + small Fargate task).
- **What to watch:** In Cost Explorer, filter by usage type for `Lambda-GB-Second`, `Lambda-Requests`, and `Aurora:ServerlessUsage`. When the serverless bill consistently trends above the cost of reserved/on-demand container infrastructure, migrate back.

### The AWS Free Tier makes Stage 0 look cheap in year one. Why is that a bad basis for an architecture decision?
- Free Tier discounts (750 hours/month of `t2/t3.micro` EC2 and RDS) expire after 12 months. Designing an architecture dependent on temporary subsidies creates a cost cliff at month 13, causing bills to spike even if user growth remains flat.

---

## 4. Authentication

### What is the difference between the ID token and the access token? Which one goes to the API?
- **ID Token:** Formatted as an OIDC JWT meant for the **client application (frontend)**. It contains identity assertions (`email`, `name`, `email_verified`, `sub`) to customize the user interface.
- **Access Token:** Formatted as an OAuth 2.0 token meant for the **resource server (API)**. It encapsulates authorization scopes, client ID, and user subject to authorize specific backend actions.
- **The Access Token goes to the API** in the `Authorization: Bearer <access_token>` header.

### Why do a public client and PKCE belong together? What does PKCE protect against that a client secret would, if the browser could keep one?
- A public client (SPA browser app) cannot securely store a static client secret because its source code and memory are accessible to the client.
- PKCE (Proof Key for Code Exchange) protects against **authorization code interception attacks**. The browser generates a dynamic, one-time `code_verifier` and sends the hashed `code_challenge` during the authorization request. When exchanging the authorization code, the browser sends the plain `code_verifier`. An attacker who intercepts the code cannot redeem it without the secret verifier held in browser session memory.

### Cognito Essentials is free up to 10,000 monthly active users. What does it cost at 50,000? And at what point would you consider running your own authentication?
- **Cost at 50,000 MAUs:**
  - First 10,000 MAUs: Free (\$0)
  - Next 40,000 MAUs: 40,000 × \$0.0055 = **\$220.00 / month**.
- **When to self-host:** When MAU counts reach hundreds of thousands (costing thousands of dollars monthly) or when custom cryptographic requirements, legacy system integration, or strict on-premise compliance dictate full ownership of the auth database.

### The same person signs up with a password, then later uses Continue with Google with the same email. Cognito now holds two users with two different `sub`s. Which of your tables break? How would you link the two accounts, and why is it dangerous to link automatically on email alone?
- **Which tables break:** Any tables referencing the user ID (`sub`) as a foreign key (e.g. `meetings.user_id`) or tables enforcing uniqueness on email. The user will see disparate data depending on which login method they used.
- **How to link:** Use a Cognito **Pre-Authentication Lambda Trigger** calling the `AdminLinkProviderForUser` API to link the federated Google identity to the existing Cognito user.
- **Why automatic linking on email alone is dangerous:** If a federated identity provider does not enforce strict email verification, an attacker could register an unverified account on that provider with the victim's email address and automatically hijack access to the victim's account upon linking.

### The Google client secret lives in Cognito, but the Cognito app client has no secret at all. Why can one side hold a secret and the other cannot?
- **Google Client Secret in Cognito:** Cognito is a managed server-side backend service. It exchanges secrets directly with Google over backchannel HTTPS server-to-server calls; the secret is never exposed to public networks.
- **Cognito App Client:** Runs client-side in the end user's web browser. Any secret stored in JavaScript, environment variables, or HTML would be instantly visible to anyone inspecting developer tools.

### Google's consent screen names your app and its domain. What does the user see there, and why does that matter for phishing?
- **What the user sees:** The registered application name, support email, privacy policy link, and the authorized domain (`<prefix>.auth.eu-north-1.amazoncognito.com`).
- **Why it matters for phishing:** Attackers can easily copy website designs, but they cannot spoof Google's official consent screen URL or disguise an unauthorized redirect domain. Users can verify that Google is authenticating them for the legitimate service and not an adversarial phishing domain.

