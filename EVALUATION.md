# Evaluation of traces toolset in [obs-mcp](https://github.com/rhobs/obs-mcp)

## Setup
[opentelemetry-demo](https://github.com/open-telemetry/opentelemetry-demo/tree/2.2.0) modified to send traces to a Tempo instance.
To generate errors, the paymentFailure flag is set to 90%.
Therefore, in 90% of the cases, the charge operation of the payment fails with `Payment request failed. Invalid token. app.loyalty.level=gold`.

Claude Code with Opus 4.6, using obs-mcp with metrics and traces toolsets enabled.

Every prompt is done with a fresh context, to prevent spilling information from one prompt eval to the next.

## Show traces for a given resource (pod, deployment)
❯ Show me traces of the payment service
* tempo_list_instances
* tempo_search_tag_values (tempoName="tempo1", tag="resource.service.name")
* tempo_search_tag_values (tempoName="tempo2", tag="resource.service.name")
* tempo_search_traces(query="{ resource.service.name=\"payment\" }")


❯ Show me traces of the payment deployment

It looked for `resource.service.name` instead.
After being more specific ("Search for the payment Kubernetes deployment, not the service."), it used the correct attribute `resource.k8s.deployment.name`.

*Improvement: mention `resource.k8s.deployment.name` attribute in toolset instructions or tool description.*

❯ Show me traces of the payment-697486d74b-s2chm pod

It ran `tempo_search_tags` and then found the `k8s.pod.name` attribute, and performed the right TraceQL query: `{ resource.k8s.pod.name = "payment-697486d74b-s2chm" }`.

*Improvement: mention `k8s.pod.name` attribute in toolset instructions or tool description.*

❯ Show me a slow trace of the payment service

It runs this query: `{ resource.service.name="payment" && duration>500ms }`

"how did you determine 500ms is slow?"

    Good point — I assumed 500ms was "slow" without any basis. I should first look at what's normal for the payment service and then find outliers relative to that baseline.
    Want me to search for all recent payment traces (no duration filter) so we can see the typical latency range, and then pick out the slowest ones?

*Improvement: update toolset instructions to first set a baseline by searching for all recent traces to get a typical latency range.*

❯ Show me error traces of the "/api/checkout" endpoint

TraceQL query: `{ span.http.route="/api/checkout" && status=error }`

It queries both Tempo instances simultaneously.

*Improvement: The MCP server instructions are truncated. According to Claude Code, the instructions were cut off at "UNDERSTAND TIME FRAMES" (from the metric toolset instructions).*

## State of the system
❯ What is the state of the payment service?

It only checks the alerts and metrics and comes to the conclusion:

    Overall, the payment service appears healthy and operational.

Instruct it to also use traces: "also verify the traces"

It runs two queries
* `{ resource.service.name="payment" }`
* `{ resource.service.name="payment" && status=error }`
* and then fetches a trace with errors

Now we get a different result:

    The payment service is running and emitting traces, but it is functionally broken — every checkout attempt fails with "Payment request failed. Invalid token. app.loyalty.level=gold". This appears to be a token validation issue specific to the gold loyalty tier. All other services in the checkout flow (cart, currency, product-catalog, quote, shipping) are operating normally.

❯ What are the dependencies of the checkout service? What are the upstream services?

It searches for traces, fetches one of them and correctly shows downstream and upstream dependencies.

    So the call chain is: load-generator → frontend-proxy → frontend → checkout → {cart, product-catalog, currency, shipping → quote, payment}.

❯ Compare trace 966011199e42e4af4fbf2112f973ebd9 with trace 9ed9e7d1ebc0ccf68750de8636811bdc

Note: The first trace has an error in the charge operation, the second trace has no error.

```
● Here's a comparison of the two traces:

  Trace Comparison

  ┌───────────────────┬───────────────────┬────────────────────┐
  │      Aspect       │ Trace 96601119... │ Trace 9ed9e7d1...  │
  ├───────────────────┼───────────────────┼────────────────────┤
  │ Outcome           │ FAILED (HTTP 500) │ SUCCESS (HTTP 200) │
  ├───────────────────┼───────────────────┼────────────────────┤
  │ Total Duration    │ ~18ms             │ ~57ms              │
  ├───────────────────┼───────────────────┼────────────────────┤
  │ Services Involved │ 9                 │ 12                 │
  ├───────────────────┼───────────────────┼────────────────────┤
  │ Cart Items        │ 4                 │ 2                  │
  └───────────────────┴───────────────────┴────────────────────┘

  Root Cause of Failure (Trace 1)

  The failing trace errors at the payment service with:

  ▎ Payment request failed. Invalid token. app.loyalty.level=gold

  The error originates in charge.js:37 in the payment service and propagates up through:
  1. payment oteldemo.PaymentService/Charge (gRPC status 2 = UNKNOWN)
  2. checkout oteldemo.CheckoutService/PlaceOrder (gRPC status 13 = INTERNAL)
  3. frontend POST /api/checkout (HTTP 500)

  Key Differences

  ┌────────────────────┬─────────────────────────────┬────────────────────────────────────────────────┐
  │        Step        │      Trace 1 (failed)       │              Trace 2 (successful)              │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Loyalty Level      │ gold                        │ bronze                                         │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Card Validation    │ Not reported (fails before) │ card_valid=true, card_type=visa                │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Payment Charged    │ No                          │ Yes (charged=true)                             │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Payment Amount     │ $267.16                     │ $61.88                                         │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Product            │ Red Flashlight (LS4PSXUNUM) │ Lens Cleaning Kit (L9ECAV7KIM)                 │
  ├────────────────────┼─────────────────────────────┼────────────────────────────────────────────────┤
  │ Post-payment steps │ None (aborted)              │ EmptyCart, ShipOrder, SendEmail, Kafka publish │
  └────────────────────┴─────────────────────────────┴────────────────────────────────────────────────┘

  Services Missing from Failed Trace

  Because the failure happens at payment, the following post-checkout steps never execute in Trace 1:
  - cart EmptyCart
  - shipping POST /ship-order
  - email POST /send_order_confirmation
  - flagd (cart failure feature flag check)
  - kafka order publish

  Summary

  The failure is caused by the payment service rejecting requests from users with loyalty level gold with an "Invalid token" error. The successful trace has a bronze loyalty level and processes
  normally. This looks like a bug in the payment service's token validation logic that specifically affects gold-tier loyalty customers.
```

❯ Show me outlier traces of the payment service

It checked for traces > 500ms and traces with errors.

Follow-up prompt: "how did you determine outliers?"

```
● Good question. I used two approaches:

  1. Latency outliers: I searched for traces with duration > 500ms, which returned zero results. That 500ms threshold was an arbitrary guess on my part — I didn't first check what normal latency
  looks like to pick a meaningful percentile-based cutoff.
  2. Error outliers: I searched for traces with status=error, which returned 10 results. Errors are a more straightforward definition of "outlier" since any error is abnormal.

  A more rigorous approach would have been to first query the p99 or p95 latency from the traces_span_metrics_duration_milliseconds histogram, then use that value as the duration threshold in Tempo
  to find traces above the normal range. Want me to do that?
```

*Improvement: Add instructions to use the RED metrics to get a baseline to find outliers.*

## Explanation

❯ Explain the error in the payment service
```
● Here's what's happening with the payment service:

  Payment Service Error: Invalid Token for Loyalty Level "gold"

  Every checkout request that hits the payment service is failing with:

  Payment request failed. Invalid token. app.loyalty.level=gold

  Root cause: The payment service's charge function (at /usr/src/app/charge.js:37) rejects the payment when the customer's loyalty level is gold. The error message indicates a token validation issue
  specific to this loyalty tier — it appears the payment service treats the gold loyalty level's token as invalid and throws an error.

  Call chain:
  1. load-generator sends a checkout request (POST /api/checkout)
  2. frontend-proxy → frontend → checkout service
  3. checkout prepares the order (cart, products, currency conversion, shipping quote — all succeed)
  4. checkout calls PaymentService/Charge to charge the card ($86.43)
  5. Payment service rejects the charge with the invalid token error
  6. The error propagates back up: checkout (gRPC status 13 INTERNAL) → frontend (HTTP 500) → load-generator

  Key details:
  - The error is consistent — all 5 recent error traces show the same pattern
  - The charge span has app.loyalty.level=gold, suggesting the service validates tokens differently per loyalty tier
  - The payment amount varies but the error is always the same
  - All other services in the chain (cart, product-catalog, currency, shipping, quote) work fine

  This looks like either a misconfigured token for gold-tier customers, or a bug in charge.js line 37 where gold-level loyalty tokens are being incorrectly validated.
```

Follow-up: "The sources are in the src folder"
```
● Now the source tells the full story. Here's the root cause:

  Root Cause: Feature Flag paymentFailure

  The error is intentionally injected via a feature flag. In charge.js:29-38:

  const numberVariant = await OpenFeature.getClient().getNumberValue("paymentFailure", 0);

  if (numberVariant > 0) {
    // n% chance to fail with app.loyalty.level=gold
    if (Math.random() < numberVariant) {
      span.setAttributes({'app.loyalty.level': 'gold' });
      span.end();
      throw new Error('Payment request failed. Invalid token. app.loyalty.level=gold');
    }
  }

  The feature flag paymentFailure returns a number between 0 and 1 representing the probability of failure. When the random check hits, the service:
  1. Hardcodes app.loyalty.level=gold on the span (it's not actually checking a real loyalty level)
  2. Throws a fake "Invalid token" error

  This is a chaos engineering / demo failure injection — the error message about "Invalid token" and "gold loyalty level" is completely synthetic. The real loyalty level assignment happens later on
  line 54 (random(LOYALTY_LEVEL)) and is never reached when the flag triggers.

  To fix it: Set the paymentFailure feature flag to 0 in your flagd configuration. That will stop the injected failures entirely.
```

## Summary of Findings

### What works well
* **Service name lookups**: Searching traces by `resource.service.name` works correctly out of the box.
* **Pod name lookups**: The model discovered `k8s.pod.name` via `tempo_search_tags` and constructed the correct query.
* **Error trace and filtering**: Queries using `status=error` and `span.http.route` work as expected.
* **Dependency mapping**: The model correctly identified upstream and downstream dependencies from a single trace.
* **Trace comparison**: Detailed side-by-side comparison with root cause analysis was accurate and thorough.
* **Root cause explanation**: When pointed to the source code, the model correctly identified the feature flag as the root cause.
* **Multi-instance support**: The model queries both Tempo instances simultaneously.

### Issues found
* **Deployment lookups require a follow-up prompt**: The model defaults to `resource.service.name` instead of `resource.k8s.deployment.name` when asked about a deployment.
* **Arbitrary latency thresholds**: When asked for "slow" or "outlier" traces, the model uses a hardcoded 500ms threshold without first establishing a baseline.
* **Traces not checked for health assessments**: When asked about the state of a service, the model only checks alerts and metrics, missing a 90% error rate visible in traces. A follow-up prompt is needed to include traces.
* **MCP server instructions truncated**: Instructions are cut off, and therfore instructions of the traces toolset are ignored.

### Suggested improvements to obs-mcp
1. Mention `resource.k8s.deployment.name` and `resource.k8s.pod.name` attributes in toolset instructions or tool descriptions.
2. Add instructions to establish a latency baseline (e.g. query recent traces or RED metrics) before filtering for slow/outlier traces.
3. Add instructions to check traces (especially error traces) when assessing service health, not just alerts and metrics.
4. Fix the MCP server instructions truncation issue.
