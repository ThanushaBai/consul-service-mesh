service {
  name = "backend"
  id   = "backend-1"
  port = 8080

  connect {
    sidecar_service {}
  }

  check {
    name     = "backend-health"
    http     = "http://localhost:8080/health"
    interval = "5s"
    timeout  = "3s"
  }
}