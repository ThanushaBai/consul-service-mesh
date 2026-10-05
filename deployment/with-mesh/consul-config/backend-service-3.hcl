service {
  name = "backend"
  id   = "backend-3"
  port = 8080

  connect {
    sidecar_service {}
  }

  check {
    name     = "backend-health-3"
    http     = "http://localhost:8080/health"
    interval = "5s"
    timeout  = "3s"
  }
}