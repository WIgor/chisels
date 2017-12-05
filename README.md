# Chisels for sysdig

## socket_latency
Measure latency between request and response  
Examples:  
`sysdig -c socket_latency "out '' 6379"` - measure output latency to redis port on any IP  
`sysdig -c socket_latency "in 127.0.0.1 80"` - measure input latency to localhost http

## http_latency

sysdig -c http_latency [filter] - measure http latency
