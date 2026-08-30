# SUSE Security (NeuVector) Demo Walkthrough: Monitor → Protect Mode

## Status
This demo guide is still a work in progress.  Technically everything works - still need to build the order of operations and "tighten up" what you click on, and what you will see for names, etc..

TODO: ensure the path demonstrates the capability in way that is easy to recognize


## Overview

This walkthrough guides you through a live demonstration of SUSE Security (NeuVector) using a running container in the `aperture-sci` namespace. You'll observe network behavior in Monitor mode, then flip to Protect mode and witness real-time enforcement blocking unauthorized connections.

---

## The Setup

Before you begin, confirm the test container is running and active. The `chell-test` container in the `aperture-sci` namespace is continuously making outbound HTTPS requests every 5 seconds:

See [Scripts/30_deploy_apps.sh](Scripts/30_deploy_apps.sh) for deploying the simple container for this demo.

```bash
kubectl get pods -n aperture-sci
```

You should see `chell-test` in a `Running` state. Internally, it's executing this loop:

```bash
curl -svo /dev/null https://www.fastly.com 2>&1 | grep subjectAltName
```

This curl call validates the TLS certificate on `www.fastly.com` and prints the Subject Alternative Name — confirming both DNS resolution and TLS negotiation are succeeding. This is your **known-good baseline traffic**.

---

## Part 1: Observing Traffic in Monitor Mode

### Step 1 — Log into the NeuVector Console

Navigate to your NeuVector management UI. From the left sidebar, go to:

**Network Activity** → you should see a live network graph populating with your cluster's workloads.

> 💡 **Tip for the audience:** NeuVector is watching every network connection at Layer 7 — not just IP/port, but protocol and payload. Everything happening right now is being recorded.

### Step 2 — Locate the `chell-test` Container

In the Network Activity view, find the `aperture-sci` namespace grouping. Click on the `chell-test` service/pod. You should see:

- An **outbound HTTPS connection** being established every ~5 seconds to `www.fastly.com`
- NeuVector recording the destination, protocol (HTTPS/443), and connection frequency

This traffic appears in **green** or as an allowed/observed connection — because NeuVector is currently in **Monitor mode**, which means it's *learning* and *alerting*, but **not blocking** anything.

### Step 3 — Review the Learned Network Rules

Navigate to **Policy** → **Network Rules** and filter to the `aperture-sci` namespace.

You should see NeuVector has auto-discovered and documented:

- **Source:** `nv.chell-test.aperture-sci` (aperture-sci namespace)
- **Destination:** `(external)`
- **Applications:** SSL **Ports** ANy

> 🎯 **Key talking point:** This is NeuVector's *behavioral baseline*. In Monitor mode, it's building a model of "what normal looks like" for this workload. Every connection gets catalogued. When you switch to Protect mode, anything that deviates from this baseline becomes a candidate for enforcement.

### Step 4 — Observe the Live Security Events

Go to **Notifications** → **Security Events**. You may see informational events being logged for the outbound connections. Notice that in Monitor mode, these are recorded but the traffic flows freely.  At this point, however, we will see no notifications for our chell-test workload

> 🎯 **Key talking point:** Your security team gets visibility without disrupting the application. This is how you build confidence before enforcing — you watch first, then act.

---

## Part 2: Switching to Protect Mode

### Step 5 — Change the Group Policy to Protect Mode

Navigate to **Policy** → **Groups**. Find the group corresponding to `chell-test` in the `aperture-sci` namespace (it may appear as `nv.chell-test.aperture-sci` or similar).

Click on the group, then look for the **Policy Mode** setting. You'll see three options:

| Mode | Behavior |
|------|----------|
| **Discover** | Learning only — no alerts, no blocks |
| **Monitor** | Alert on violations — no blocks |
| **Protect** | Enforce — violations are **blocked** |

Select **Protect** and confirm. The change takes effect immediately — NeuVector's enforcement engine now has an active ruleset for this workload.

> 🎯 **Key talking point:** This is a per-group, per-workload control. You can have some services in Discover, others in Monitor, and production-critical workloads in Protect — all simultaneously. Granularity is the point.

### Step 6 — Verify the Legitimate Traffic Still Flows

Give it 10–15 seconds. The `chell-test` container's existing curl loop to `www.fastly.com` should **continue to work** because NeuVector learned that connection during the Monitor phase and it is now part of the allowlist.

You can verify by watching the logs:

```bash
kubectl logs -f $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci
```

You should continue to see output like:

```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

> 🎯 **Key talking point:** Legitimate, learned traffic is unaffected. NeuVector enforces *zero-trust* — not *zero-connectivity*. The model is "deny everything not explicitly allowed," but the allowlist was built automatically from observed behavior.

---

## Part 3: Demonstrating Enforcement (Protect Mode in Action)

### Step 7 — Exec into the Container

Now you'll attempt connections that were never part of the learned baseline.

```bash
kubectl exec -it $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci -- /bin/sh
```
And you will see
```
~ # command terminated with exit code 137
```

Hmmm... let's try /bin/bash
```
kubectl exec -it $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci -- /bin/bash
command terminated with exit code 137
```

This is actually expected.  Browse to Notifications | Security Events

You should now see a few entries - 1 for /bin/sh and 1 for /bin/bash.  Click on "Rewrite Rule" - the dialogue presents a warning with a red background.  Review the warning and then click "Deploy"

And... let's try again to get a shell
```
kubectl exec -it $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci -- /bin/sh
~ #
```

Huzzah!  You should get a shell prompt inside the container.

### Step 8 — Attempt an Unauthorized Connection (curl to google.com)

From inside the container, run:

```bash
curl google.com
```

**Expected result:** The connection is **blocked**. You'll see either a connection timeout, connection refused, or an immediate failure — NeuVector's enforcement engine drops the packet before it leaves the container's network namespace.

```
Killed
```

Refresh your view in Notifications | Security Events

> 🎯 **Key talking point:** `google.com` was never part of this container's learned behavior. NeuVector has no rule permitting it, so in Protect mode it doesn't get through — full stop. This is east-west and north-south enforcement at the container level, not at the perimeter.

Back in the NeuVector console, navigate to **Notifications** → **Security Events**. You should see a **violation event** with:

- Source: `chell-test`
- Destination: `google.com`
- Action: **Denied / Blocked**
- Timestamp matching your attempt

This is yet another subtle incident.  You can rewrite the rule to allow curl to run "Process profile rule violation by process "curl", and attempt the curl again
```
~ # curl google.com
curl: (56) Recv failure: Connection reset by peer
```
Refresh your Security Events and you will now see "Implicit deny rule was violated" - you will need to rewrite that rule, as well.

> You can start to see how granular and subesequently powerful this tool can be.

### Step 9 — Attempt a Second Unauthorized Connection (wget to fastly.com)

Still inside the container, run:

```bash
wget https://www.fastly.com 2>&1 | grep subjectAltName
```

**Expected result:** This connection is also **blocked**, even though the *destination* (`www.fastly.com`) was in the learned baseline.

> 🎯 **Key talking point:** This is the subtle but critical part. `wget` is a *different process* with a *different network behavior signature* than `curl`. NeuVector enforces at the process level — not just destination IP. The allowed rule was built for `curl` making HTTPS connections on a 5-second cycle. `wget` in an interactive shell session doesn't match that profile, so it's denied.

> This is how you catch lateral movement and container compromise — an attacker who gains shell access can't just `wget` an exfiltration endpoint or phone home, even if that endpoint was legitimately used by the application itself.

You should see a second violation event in the NeuVector console for this attempt as well.

Lets Rewrite Rule for wget and try again.  It still fails (refresh NeuVector and you'll see why: grep was not allow-listed).  Go ahead and rewrite for grep.  

> Again, you should start to recognize how granular the controls can be - which is effective in mitigating the "unknown" vulnerabilities that might be attempted.

Go ahead and exit the container
```
~ # exit
command terminated with exit code 1
```

---

## Part 4: Blocking a Specific Domain

### Step 10a — Confirm Baseline Traffic is Still Flowing

Before implementing the block, confirm that the automated `curl` loop is still successfully reaching `www.fastly.com`. From a separate terminal (outside the container):

```bash
kubectl logs -f $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci
```

You should still see the familiar output every ~5 seconds:

```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

> 🎯 **Key talking point:** This is the *currently allowed* baseline. We're about to change that — in real time, with zero restarts or redeployments.

### Step 10b — Create an Address Group for *.fastly.com

Before creating the deny rule, you need a named group that represents the Fastly domain. Navigate to **Policy** → **Groups** and click **Add**.

| Field | Value |
|-------|-------|
| **Name** | `fastly-external` |
| **Criteria** | `address=*.fastly.com` |

Click **Add** to save the group. This gives NeuVector a target it can match by FQDN — without it, any rule targeting `external` would apply to *all* outbound traffic, not just Fastly.

### Step 10c — Create the Deny Rule

Navigate to **Policy** → **Network Rules** and click **Add To Top**:

| Field | Value |
|-------|-------|
| **From** | `nv.chell-test.aperture-sci` |
| **To** | `fastly-external` |
| **Ports** | `443` |
| **Action** | **Deny** |
| **Comment** | `Block *.fastly.com` |

> ⚠️ **Order matters.** Using **Add To Top** ensures the Deny rule evaluates before any existing allow rules. NeuVector evaluates rules top-down — the first match wins.

Click **Deploy** to push the ruleset.

### Step 10d — Observe the Block Taking Effect

Watch the container logs. Within one cycle (≤5 seconds), the output will stop — or you'll see a connection failure instead of the `subjectAltName` line:

```bash
kubectl logs -f $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci
```

The loop is still running inside the container — `curl` is still attempting the connection every 5 seconds — but NeuVector is now dropping it before it reaches the network.

In **Notifications** → **Security Events** you should see a stream of **Deny** events:

- **Source:** `chell-test`
- **Destination:** `www.fastly.com`
- **Port:** `443`
- **Action:** **Denied**

> 🎯 **Key talking point:** We just changed enforcement policy on a live, running workload with no restart, no redeployment, and no changes to the container image or Kubernetes manifests. The policy lives in NeuVector — independent of the workload. This is the operational model for runtime security: the application doesn't need to know anything about the enforcement layer.

### Step 10e — Remove the Block Rule (Cleanup)

To restore baseline traffic for the rest of the demo:

1. **Policy** → **Network Rules** — delete the `Block *.fastly.com` deny rule, click **Deploy**
2. **Policy** → **Groups** — delete the `fastly-external` address group

The `curl` log output will resume within one cycle.

---

## Part 5: WAF (Web Application Firewall) Demo

NeuVector includes a built-in WAF engine that inspects HTTP/HTTPS payloads at Layer 7 — beyond just "who is talking to whom" and into *what they're saying*. This section demonstrates how WAF rules catch common attack patterns like SQL injection and path traversal, even from within an otherwise-allowed container.

### Step 11 — Create a WAF Sensor

Navigate to **Policy** → **WAF Sensors** and click **Add**.

| Field | Value |
|-------|-------|
| **Name** | `aperture-waf` |
| **Comment** | `Demo WAF sensor for aperture-sci` |

Once the sensor is created, click into it and click **Add Rule** to define patterns:

**Rule 1 — SQL Injection:**

| Field | Value |
|-------|-------|
| **Name** | `sql-injection` |
| **Pattern** | `(?i)(union.*select\|select.*from\|'\s*or\s*'1'\s*=\s*'1\|'\s*or\s*1\s*=\s*1)` |
| **Context** | `url` |

**Rule 2 — Path Traversal:**

| Field | Value |
|-------|-------|
| **Name** | `path-traversal` |
| **Pattern** | `(\.\./\|%2e%2e%2f\|%2e%2e/)` |
| **Context** | `url` |

Click **Save** to commit the sensor.

> 💡 **Tip:** NeuVector also ships with built-in WAF signatures you can import. The manual rules here are to make the pattern-matching logic visible and auditable.

### Step 12 — Apply the WAF Sensor to the Group

Navigate to **Policy** → **Groups** → `nv.chell-test.aperture-sci`.

Click **WAF** (tab or section within the group detail). Click **Add** and select `aperture-waf`. Set the action to **Alert** first so you can observe before blocking.

Click **Deploy**.

> 🎯 **Key talking point:** WAF sensors are applied per-group, just like policy modes. You can have different WAF postures for different workloads — a front-end service might get full OWASP coverage while an internal metrics scraper gets none. Granularity again.

### Step 13 — Trigger a SQL Injection Alert

Exec into the `chell-test` container:

```bash
kubectl exec -it $(kubectl get pods -n aperture-sci -o custom-columns=":metadata.name" --no-headers) -n aperture-sci -- /bin/sh
```

From inside the container, send a request with a SQL injection payload in the URL:

```bash
curl -sk "https://www.fastly.com/path?id=1%27%20OR%20%271%27%3D%271"
```

The request may succeed (because the sensor is in **Alert** mode), but navigate to **Notifications** → **Security Events** and you should see a WAF event:

- **Type:** WAF
- **Sensor:** `aperture-waf`
- **Rule:** `sql-injection`
- **Source:** `chell-test`
- **Action:** Alert

> 🎯 **Key talking point:** The network rule allowed this connection — `fastly.com` on port 443 is in the learned baseline. But the WAF caught what the network rule couldn't: a malicious payload inside the allowed channel. This is the difference between network security and application security.

### Step 14 — Switch WAF to Deny and Verify Blocking

Go back to **Policy** → **Groups** → `nv.chell-test.aperture-sci` → **WAF**. Change the action for `aperture-waf` from **Alert** to **Deny**. Click **Deploy**.

From inside the container, repeat the request:

```bash
curl -sk "https://www.fastly.com/path?id=1%27%20OR%20%271%27%3D%271"
```

**Expected result:** The connection is **blocked**. You'll see a failure or no response.

Also test the path traversal rule:

```bash
curl -sk "https://www.fastly.com/../../etc/passwd"
```

Both should be blocked. Return to **Notifications** → **Security Events** — you'll now see **Deny** WAF events for each attempt.

> 🎯 **Key talking point:** The container is allowed to talk to Fastly — that hasn't changed. But now the *content* of those allowed requests is also policed. An attacker who compromises this container and tries to use it as a pivot for a web-based attack gets stopped by NeuVector, not by a perimeter firewall they might not even reach.

### Step 15 — WAF Cleanup

Remove the WAF sensor from the group before proceeding:

1. **Policy** → **Groups** → `nv.chell-test.aperture-sci` → **WAF** — remove `aperture-waf`, click **Deploy**
2. **Policy** → **WAF Sensors** — delete `aperture-waf`

---

## Part 6: Closing the Loop

### Step 16 — Review the Violation Timeline

In **Notifications** → **Security Events**, review the violation events side by side. Point out:

- **What was attempted** (process, destination, protocol, payload)
- **What action NeuVector took** (blocked)
- **How this maps to a real threat scenario** — unauthorized outbound connections, potential C2 callout, data exfiltration attempt, web-based attack pivoting

### Step 17 — Optional: Show the Network Graph Differential

Return to **Network Activity**. The attempted (blocked) connections may appear as **red dotted lines** in the network graph — visually distinct from the green allowed connection to Fastly. This gives a clear "what was allowed vs. what was blocked" picture for a non-technical audience.

---

## Demo Summary

| Action | Mode | Result |
|--------|------|--------|
| `curl fastly.com` (automated loop) | Monitor | ✅ Allowed — observed and logged |
| Switch to Protect | — | Enforcement enabled, learned rules become policy |
| `curl fastly.com` (automated loop) | Protect | ✅ Allowed — matches learned baseline |
| `curl google.com` (interactive) | Protect | 🚫 Blocked — no learned rule exists |
| `wget fastly.com` (interactive) | Protect | 🚫 Blocked — process signature mismatch |
| `curl fastly.com?id=SQL_INJECT` | WAF Alert | ⚠️ Allowed but alerted — WAF pattern match |
| `curl fastly.com?id=SQL_INJECT` | WAF Deny | 🚫 Blocked — WAF enforcement on HTTP payload |
| `curl fastly.com/../../etc/passwd` | WAF Deny | 🚫 Blocked — WAF path traversal rule |

---

## Key Takeaways for Your Audience

**Behavioral baseline, not signature-based.** NeuVector doesn't use CVE signatures to block things. It models what "normal" looks like for each workload and enforces that model. Zero-day exploits that use legitimate-looking processes still get caught.

**Process-level enforcement.** The unit of enforcement isn't IP or port — it's the container process making the connection. This is enforcement inside the pod, before traffic ever hits the network.

**Graduated rollout.** Discover → Monitor → Protect gives operators the ability to build confidence before enforcing. You don't have to choose between blind blocking and total permissiveness.

**Full audit trail.** Every allowed and blocked connection is logged with enough context to reconstruct what happened, when, and from where — directly satisfying audit and compliance requirements for IL4/IL5 environments.

**Layer 7 WAF built in.** NeuVector's WAF engine inspects HTTP payload content — URL parameters, headers, and body — for attack patterns like SQL injection, XSS, and path traversal. This is application-layer protection without a separate appliance, operating inside the cluster on a per-workload basis.
