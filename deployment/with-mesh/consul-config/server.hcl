datacenter = "dc1"
data_dir   = "/consul/data"
log_level  = "INFO"
node_name  = "consul-server"

server           = true
bootstrap_expect = 1

bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"

ports {
  grpc     = 8502
  http     = 8500
  https    = -1
  dns      = 8600
  server   = 8300
  serf_lan = 8301
  serf_wan = 8302
}

connect {
  enabled = true
}

ui_config {
  enabled = true
}

addresses {
  http  = "0.0.0.0"
  https = "0.0.0.0"
  grpc  = "0.0.0.0"
  dns   = "0.0.0.0"
}