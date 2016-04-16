# Chisels for sysdig

## socket_latency
Measure latency between request and response  
Examples:  
`sysdig -c socket_latency "out '' 6379"` - measure output latency to redis port on any IP  
`sysdig -c socket_latency "in '' 80"` - measure input latency to local http
