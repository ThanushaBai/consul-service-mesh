datacenter  = "dc1"
data_dir    = "/consul/data"
log_level   = "INFO"
client_addr = "0.0.0.0"
bind_addr   = "0.0.0.0"

ports {
  grpc = 8502
  http = 8500
}

connect {
  enabled = true
}