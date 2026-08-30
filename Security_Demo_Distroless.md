# SUSE Security (NeuVector) Demo Walkthrough: Distroless Containers

## Status

Narrative draft — not yet built. Hand this to Claude Code to generate the Dockerfile, app source, K8s manifests, and deploy script. Companion to `Security_Demo.md` (the `chell-test`/`aperture-sci` walkthrough) — that demo uses `nicolaka/netshoot`, a fully-loaded shell image. This one deliberately uses a **true distroless image** (no shell, no package manager, no coreutils) to show a different angle: what happens when the "exec in and run tools" attack path is closed at the image layer, and how SUSE Security still catches an attacker who works around that.

TODO once built: confirm exact wording/tab names for the ephemeral-container event in Notifications → Security Events (may vary by NeuVector version) — same "tighten up what you click on" caveat as the original doc.

## Overview

This walkthrough uses a minimal, distroless "small web server" workload (`wheatley`) in a new namespace (`aperture-labs`) to demonstrate:

1. Deploying a distroless container and confirming it works as a normal web service.
2. Why `kubectl exec` straight into it fails outright — there is no shell to run — and how you actually get a foothold anyway (`kubectl debug` ephemeral container), which is the real-world technique attackers and admins both use against shell-less images.
3. Pulling a resource from the internet that resembles malware/a vulnerability payload, first in **Monitor** mode (logged, not blocked), then in **Protect** mode (blocked/killed).

The point for the audience: distroless removes the *easy* attack surface (no shell, no tools to abuse), but it doesn't remove risk entirely — someone can still attach tooling alongside the pod. SUSE Security is the layer that catches what image hardening alone can't: unrecognized processes and unrecognized network egress, enforced at runtime, regardless of how minimal or hardened the image is.

---

## The Setup

### The app: `wheatley`

A tiny statically-linked Go HTTP server (`wheatley-server`), built multi-stage:

```
# builder stage
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o wheatley-server main.go

# final stage — true distroless, no shell, no package manager
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /src/wheatley-server /wheatley-server
EXPOSE 8080
ENTRYPOINT ["/wheatley-server"]
```

`main.go` just needs to serve something Portal-flavored on `:8080`, e.g. `GET /` → `"I am NOT a moron... but I might be a tiny bit thick."` and `GET /healthz` → `200 OK`. Keep it to one binary, one process, no forking, no shelling out — that's what makes the learned baseline so tight and the demo so clean.

Push the image to whatever registry the cluster can pull from (Harbor/local registry per the homelab setup).

### The manifest

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: aperture-labs
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wheatley
  namespace: aperture-labs
  labels:
    app: wheatley
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wheatley
  template:
    metadata:
      labels:
        app: wheatley
    spec:
      containers:
        - name: wheatley
          image: <your-registry>/wheatley-server:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: wheatley
  namespace: aperture-labs
spec:
  selector:
    app: wheatley
  ports:
    - port: 8080
      targetPort: 8080
```

No `shareProcessNamespace`, no debug sidecar baked in — the pod is exactly as minimal as it looks. That's deliberate; the "how do you get in" step below only works because Kubernetes gives you a side door that doesn't require the image to cooperate.

Suggested script name for Claude Code to produce: `Scripts/31_deploy_distroless.sh`, following the same pattern as `30_deploy_apps.sh` (source `env.sh`, apply the manifest, print next steps).

---

## Part 0: Deploy and Confirm It's a Real Web Server

```
kubectl apply -f wheatley.yaml
kubectl get pods -n aperture-labs
kubectl port-forward -n aperture-labs svc/wheatley 8080:8080 &
curl localhost:8080/
```

You should get the Portal-flavored response back. This proves it's a working app before anyone tries to break it — worth a beat with the audience: "this is a fully functional web server. It just happens to contain nothing an attacker could use if they got inside it."

Let it run for a couple of minutes untouched. In NeuVector, this is the group's **Discover** phase — it's learning that `wheatley`'s only normal behavior is: one process, listening on 8080, no outbound connections. That tight baseline is what makes every subsequent step obviously anomalous.

---

## Part 1: Observing in Monitor Mode

### Step 1 — Find the group and set it to Monitor

**Policy → Groups** → find `nv.wheatley.aperture-labs` (or however it's auto-named). Set **Policy Mode** to **Monitor**.

> 🎯 **Key talking point:** Same three modes as the last demo — Discover, Monitor, Protect. Nothing new about the mechanism. What's different this time is the *workload*.

### Step 2 — Try the obvious thing: `kubectl exec`

```
kubectl exec -it -n aperture-labs $(kubectl get pods -n aperture-labs -o custom-columns=":metadata.name" --no-headers) -- /bin/sh
```

Expected result:

```
OCI runtime exec failed: exec failed: unable to start container process: exec: "/bin/sh": stat /bin/sh: no such file or directory: unknown
```

> 🎯 **Key talking point:** This isn't NeuVector — this is the image itself. There is no shell binary in this container, full stop. Compare this to the `chell-test` demo, where `/bin/sh` and `/bin/bash` both exist and NeuVector has to kill the resulting process after the fact. Here, the attack surface is gone *before* SUSE Security ever gets involved. This is defense in depth: harden the image first, then let runtime security catch what image hardening can't.

### Step 3 — Get in anyway: `kubectl debug`

This is the realistic move — for an attacker with `exec`/`debug` RBAC permissions, or an admin troubleshooting a shell-less pod:

```
kubectl debug -it -n aperture-labs \
  $(kubectl get pods -n aperture-labs -o custom-columns=":metadata.name" --no-headers) \
  --image=busybox:1.36 \
  --target=wheatley
```

This attaches an **ephemeral container** to the running pod. It shares the pod's network namespace (always) and, on most CRI runtimes, the target container's process namespace too — so from inside it, `ps` will show `wheatley`'s process. You now have a shell, tools, and a network path that the original image never provided.

> 🎯 **Key talking point:** Removing the shell from the image doesn't remove the side door Kubernetes itself provides. This is exactly the kind of technique real attackers use against hardened/distroless containers — and exactly why runtime security still matters even when you've done everything right at the image layer.

Check Notifications → Security Events — depending on version/config, you may see an event logged for the new/unrecognized container attaching to the pod. Note it, but don't oversell it — the real enforcement moment is next.

### Step 4 — Pull something that resembles a vulnerability payload

From inside the `busybox` debug shell:

```
wget -O /tmp/eicar.txt https://secure.eicar.org/eicar.com.txt
cat /tmp/eicar.txt
```

The EICAR string is the industry-standard, completely harmless "test virus" every AV/EDR vendor recognizes — safe to actually download live in a demo, and it universally reads as "this is what a malicious payload looks like" to the audience without anyone needing to explain what it is.

Expected result in Monitor mode: **it works.** The file downloads.

Refresh **Notifications → Security Events**. You should now see violation entries logged for:
- An unrecognized process (`wget`, `sh`/`busybox`) never part of the learned baseline
- An outbound connection to `secure.eicar.org`, a destination never part of the learned baseline

Nothing blocked yet — that's Monitor mode.

> 🎯 **Key talking point:** SUSE Security saw all of it — the shell, the tool, the destination — and logged every step, even though the connection succeeded. Your security team has full visibility into an attempted foothold before you've enforced anything.

---

## Part 2: Switching to Protect Mode

### Step 5 — Flip the group

**Policy → Groups** → `nv.wheatley.aperture-labs` → **Policy Mode** → **Protect** → confirm.

> 🎯 **Key talking point:** Same granularity point as before — `wheatley` can be in Protect while other workloads in the cluster stay in Discover or Monitor. This is a per-workload dial, not an all-or-nothing switch.

### Step 6 — Confirm the app itself is unaffected

```
curl localhost:8080/
```

Still works — the learned baseline (listen on 8080, serve HTTP) is exactly what Protect mode allows. Nothing about the app's real behavior changes.

---

## Part 3: Enforcement

### Step 7 — Try to get back in

```
kubectl debug -it -n aperture-labs \
  $(kubectl get pods -n aperture-labs -o custom-columns=":metadata.name" --no-headers) \
  --image=busybox:1.36 \
  --target=wheatley
```

Kubernetes will still let you *attach* the ephemeral container — that's a cluster RBAC/admission decision, not something SUSE Security governs. But watch what happens the moment it tries to do anything:

```
ps aux
```

or just the shell prompt itself may terminate — expect a `command terminated with exit code 137` pattern, the same SIGKILL signature seen in the `chell-test` demo. NeuVector's enforcement engine is killing the unrecognized process the instant it runs, because nothing about `busybox`/`sh` was ever part of `wheatley`'s learned baseline.

> 🎯 **Key talking point:** This is the layered-defense story in one line: Kubernetes RBAC decides *who* can attach a debug container — that's a cluster-admin/policy question, not NeuVector's job. SUSE Security decides what that debug container is *allowed to do* once it's there — and the answer, in Protect mode, is nothing outside the learned baseline.

If the shell survives long enough to issue a command, retry the exact Part 1 sequence:

```
wget -O /tmp/eicar.txt https://secure.eicar.org/eicar.com.txt
```

Expected result: blocked — connection refused/reset, or the process killed outright, mirroring the `curl google.com` moment from the original demo. Refresh **Notifications → Security Events** — you should see **Deny**/**Denied** entries for both the process and the network connection, timestamped to this attempt.

> 🎯 **Key talking point:** Same enforcement engine, same behavioral model, just applied to a workload with a dramatically smaller attack surface to begin with. The lesson for the audience: distroless is a great first layer, but "no shell in the image" and "no runtime enforcement" are two different guarantees. You want both.

### Step 8 — Optional: rewrite-rule dance

If you want to echo the original demo's granularity beat, click **Rewrite Rule** on one of the violations, review the warning, **Deploy**, and show that `wheatley`'s baseline is now durable policy independent of the image — you could swap the image entirely and the rule would still apply to anything matching that group's identity.

---

## Demo Summary

| Action | Mode | Result |
| --- | --- | --- |
| `curl localhost:8080/` | Discover/Monitor/Protect | ✅ Allowed — matches learned baseline throughout |
| `kubectl exec -- /bin/sh` | any | 🚫 Fails immediately — no shell in the image (not NeuVector; image hardening) |
| `kubectl debug --target=wheatley` (attach busybox) | Monitor | ✅ Attaches — logged as unrecognized process/container |
| `wget eicar.com.txt` (via debug shell) | Monitor | ✅ Succeeds — logged as process + network anomaly, not blocked |
| `kubectl debug --target=wheatley` (attach busybox) | Protect | ⚠️ Still attaches (K8s RBAC territory) — but anything it runs is immediately killed |
| `wget eicar.com.txt` (via debug shell) | Protect | 🚫 Blocked/killed — process + network violation enforced |

---

## Key Takeaways for Your Audience

**Image hardening and runtime security solve different problems.** Distroless closes off the "exec in and use built-in tools" path entirely. It does nothing about someone attaching new tooling to the pod via Kubernetes itself. You need both layers.

**The behavioral baseline scales down as well as up.** A single-binary, single-process, no-egress workload gets an extremely tight learned baseline — which makes anomalies (a shell, a new process, any egress at all) trivially obvious to detect and enforce against.

**Enforcement doesn't care what image you used.** The same Discover → Monitor → Protect model, the same process- and network-level kill/deny behavior from the `chell-test` demo applies here — proving the control is about *behavior*, not about trusting the image to police itself.

**RBAC and runtime security are complementary, not redundant.** Whether `kubectl debug` should be allowed against production pods at all is a cluster access-control question. What that debug session is allowed to *do* once attached is a SUSE Security question. Say this explicitly — it's the sophisticated point that separates this demo from a simple "look, it blocks stuff" pitch.
