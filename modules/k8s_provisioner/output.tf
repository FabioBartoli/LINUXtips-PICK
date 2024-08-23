output "control_plane_public_ip" {
  value = aws_instance.control_plane.public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}

output "k8s_alb_dns_name" {
  description = "DNS name of the Kubernetes control plane ALB"
  value       = aws_lb.k8s_alb.dns_name
}