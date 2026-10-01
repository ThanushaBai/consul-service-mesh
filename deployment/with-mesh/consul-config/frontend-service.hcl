service {
  name = "frontend"
  id   = "frontend-1"
  port = 8080

  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "backend"
            local_bind_port  = 9191
          }
        ]
      }
    }
  }

  check {
    name     = "frontend-health"
    http     = "http://localhost:8080/health"
    interval = "5s"
    timeout  = "3s"
  }
}