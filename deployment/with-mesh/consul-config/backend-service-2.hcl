service {
  name = "backend"
  id   = "backend-2"
  port = 8080

  connect {
    sidecar_service {}
  }

  check {
    name     = "backend-health-2"
    http     = "http://localhost:8080/health"
    interval = "5s"
    timeout  = "3s"
  }
}