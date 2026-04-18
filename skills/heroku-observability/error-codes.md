# Heroku Error Codes

Full reference. Each code appears in logs as `code=XNN` (source=heroku).

## H-codes — router / dyno errors

|Code   |Meaning                           |First thing to check                                             |
|-------|----------------------------------|-----------------------------------------------------------------|
|**H10**|App crashed                       |`--source app` for pre-crash stack; boot command; missing env var|
|**H11**|Backlog too deep                  |Throughput spike; scale web dynos; slow handlers                 |
|**H12**|Request timeout (30s)             |Slow endpoint, blocking I/O, slow DB query                       |
|**H13**|Connection closed without response|App closed socket before writing response                        |
|**H14**|No web dynos running              |`heroku ps:scale web=1`                                          |
|**H15**|Idle connection                   |Client open > 55s with no data                                   |
|**H16**|Redirect to herokuapp.com         |Missing custom domain config                                     |
|**H17**|Poorly formatted HTTP response    |App emitted malformed response                                   |
|**H18**|Server request interrupted        |Dyno/app/client closed TCP mid-response                          |
|**H19**|Backend connection timeout (5s)   |Router couldn’t connect to dyno; dyno overloaded or starting     |
|**H20**|App boot timeout                  |60s web / 75s other; migrations, slow imports, failing preboot   |
|**H21**|Backend connection refused        |Dyno refusing connections; wrong PORT binding                    |
|**H22**|Connection limit reached          |Too many concurrent conns per dyno                               |
|**H23**|Endpoint misconfigured            |Private Space networking issue                                   |
|**H24**|Forced close                      |Router closed connection (stack upgrade etc.)                    |
|**H25**|HTTP Restriction                  |Request violated protocol                                        |
|**H26**|Request error                     |Malformed request                                                |
|**H27**|Client request interrupted        |Client hung up before response                                   |
|**H28**|Client connection idle            |No data from client for 55s                                      |
|**H80**|Maintenance mode                  |`heroku maintenance:off` to disable                              |
|**H81**|Blank app                         |No code deployed                                                 |
|**H82**|Eco/Basic hours exhausted         |Account-level free dyno hours used up                            |
|**H99**|Platform error                    |Heroku-side; check status.heroku.com                             |

## R-codes — runtime errors

|Code   |Meaning                     |First thing to check                         |
|-------|----------------------------|---------------------------------------------|
|**R10**|Boot timeout (60s web)      |Same causes as H20 from runtime view         |
|**R12**|Exit timeout                |App didn’t shut down in 30s on SIGTERM       |
|**R13**|Attach error                |`heroku run` couldn’t attach                 |
|**R14**|Memory quota exceeded       |Swapping; upsize or fix leak                 |
|**R15**|Memory quota vastly exceeded|Dyno killed; hard leak or way undersized     |
|**R16**|Detached                    |Orphan process; missing foreman/procfile bind|
|**R17**|Checksum error              |Slug corruption; redeploy                    |
|**R99**|Platform error              |Heroku-side                                  |

## L-codes — Logplex

|Code   |Meaning                            |Action                                         |
|-------|-----------------------------------|-----------------------------------------------|
|**L10**|Drain buffer overflow              |Reduce log volume or move to a drain           |
|**L11**|Tail buffer overflow               |You’re losing `heroku logs` lines; add a drain |
|**L12**|Local buffer overflow              |Dyno producing logs faster than logplex accepts|
|**L13**|Local delivery error               |Transient                                      |
|**L14**|Certificate validation error       |Drain endpoint cert issue                      |
|**L15**|Tail buffer temporarily unavailable|Transient                                      |

## Quick triage mapping

- **Spike of H12/H13** → app slow or hanging; check DB / external calls / p95 latency
- **H10 after a release** → rollback candidate; diff releases
- **R14 → R15 progression** → memory leak; heap dump; restart buys time but won’t fix
- **H19 + dyno just started** → boot is slow or health check racing; check `R10`/`H20` nearby
- **L11 while investigating** → you’re missing lines; re-query with `-n 1500` max and consider a drain
- **H20 after deploy** → long migration in release phase; move to background job