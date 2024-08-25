resource "aws_key_pair" "k8s_key" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_security_group" "this" {
  count = var.instance_count

  vpc_id = var.vpc_id

  dynamic "ingress" {
    for_each = var.security_group_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = var.security_group_rules
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Name = "PICK-K8S-SG-Instance-${count.index + 1}"
  }
}

resource "aws_subnet" "k8s_subnet" {
  vpc_id            = var.vpc_id
  cidr_block        = var.k8s_subnet_cidr
  availability_zone = var.k8s_subnet_az

  map_public_ip_on_launch = true

  tags = {
    Name = "PICK-K8S-Subnet"
  }
}

resource "aws_subnet" "k8s_subnet_2" {
  vpc_id            = var.vpc_id
  cidr_block        = var.k8s_subnet_cidr_2
  availability_zone = var.k8s_subnet_az_2

  map_public_ip_on_launch = true

  tags = {
    Name = "PICK-K8S-Subnet-2"
  }
}

resource "aws_instance" "control_plane" {
  ami           = var.ami
  instance_type = var.cp_instance_type
  key_name      = aws_key_pair.k8s_key.key_name
  subnet_id     = aws_subnet.k8s_subnet.id

  root_block_device {
    volume_size = var.volume_size
  }

  vpc_security_group_ids = [aws_security_group.this[0].id]

  tags = {
    Name = "PICK-K8S-Control-Plane"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      cat <<EOF2 | sudo tee /etc/modules-load.d/k8s.conf
      overlay
      br_netfilter
      EOF2
      sudo modprobe overlay
      sudo modprobe br_netfilter
      cat <<EOF2 | sudo tee /etc/sysctl.d/k8s.conf
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
      EOF2
      sudo sysctl --system
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      sudo apt-get update && sudo apt-get install -y systemd apt-transport-https ca-certificates curl gpg unzip bash-completion
      sudo hostnamectl set-hostname PICK-control-plane
      unzip awscliv2.zip
      sudo ./aws/install
      mkdir -p ~/.aws
      echo "[default]" | tee ~/.aws/config
      echo "aws_access_key_id=${var.AWS_ACCESS_KEY_ID}" | tee -a ~/.aws/config
      echo "aws_secret_access_key=${var.AWS_SECRET_ACCESS_KEY}" | tee -a ~/.aws/config
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
      sudo apt-get update
      sudo apt-get install -y kubelet kubeadm kubectl
      sudo apt-mark hold kubelet kubeadm kubectl
      sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update && sudo apt-get install -y containerd.io
      sudo containerd config default | sudo tee /etc/containerd/config.toml
      sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
      sudo sed -i 's/^KUBELET_EXTRA_ARGS=.*/KUBELET_EXTRA_ARGS=--max-pods=110/' /etc/default/kubelet
      sudo systemctl restart containerd
      sudo systemctl enable --now kubelet
      sudo kubeadm init --pod-network-cidr=10.10.0.0/16 --apiserver-advertise-address=${aws_instance.control_plane.private_ip} --ignore-preflight-errors=NumCPU,Mem
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config
      ################ INSTALAR AUTOCOMPLETE E ALIAS ######################
      kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
      echo 'alias k=kubectl' >>~/.bashrc
      echo 'complete -F __start_kubectl k' >>~/.bashrc
      #####################################################################
      JOIN_COMMAND=$(kubeadm token create --print-join-command)
      aws ssm put-parameter --name "k8s_join_command" --value "$JOIN_COMMAND" --type "SecureString" --overwrite
      KUBECONFIG_FILE=$(cat ~/.kube/config)
      aws ssm put-parameter --name "k8s_kubeconfig" --value "$KUBECONFIG_FILE" --type "SecureString" --tier Advanced --overwrite
      #WeaveNet
      kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
      EOF
    ]

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ubuntu"
      private_key = var.private_key
    }
  }
}

resource "aws_lb" "k8s_alb" {
  name               = "k8s-control-plane-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this[0].id]
  subnets            = [aws_subnet.k8s_subnet.id, aws_subnet.k8s_subnet_2.id]

  enable_deletion_protection = false
  idle_timeout               = 60

  tags = {
    Name = "PICK-K8S-Control-Plane-ALB"
  }
}

resource "aws_lb_target_group" "k8s_tg_https" {
  name        = "k8s-control-plane-tg-https"
  port        = 30443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "k8s_tg_attachment_https" {
  target_group_arn = aws_lb_target_group.k8s_tg_https.arn
  target_id        = aws_instance.control_plane.id
  port             = 30443
}

resource "aws_lb_listener" "k8s_listener_http" {
  load_balancer_arn = aws_lb.k8s_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "k8s_listener_https" {
  load_balancer_arn = aws_lb.k8s_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:381492273741:certificate/48066b99-9cc7-46f1-9e08-31aaeeb1a735"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_tg_https.arn
  }
}

resource "aws_route53_record" "dns_records" {
  for_each = toset(var.dns_names)
  zone_id  = "Z0250850H44ROGORV6C9"
  name     = each.value
  type     = "A"

  alias {
    name                   = aws_lb.k8s_alb.dns_name
    zone_id                = aws_lb.k8s_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_instance" "worker" {
  count         = var.instance_count - 1
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.k8s_key.key_name
  subnet_id     = aws_subnet.k8s_subnet.id

  root_block_device {
    volume_size = var.volume_size
  }

  vpc_security_group_ids = [aws_security_group.this[count.index + 1].id]

  tags = {
    Name = "PICK-K8S-Worker-${count.index + 1}"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      cat <<EOF2 | sudo tee /etc/modules-load.d/k8s.conf
      overlay
      br_netfilter
      EOF2
      sudo modprobe overlay
      sudo modprobe br_netfilter
      cat <<EOF2 | sudo tee /etc/sysctl.d/k8s.conf
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
      EOF2
      sudo sysctl --system
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      sudo apt-get update && sudo apt-get install -y systemd apt-transport-https ca-certificates curl gpg unzip bash-completion
      sudo hostnamectl set-hostname PICK-worker-${count.index + 1}
      unzip awscliv2.zip
      sudo ./aws/install
      mkdir -p ~/.aws
      echo "[default]" | tee ~/.aws/config
      echo "aws_access_key_id=${var.AWS_ACCESS_KEY_ID}" | tee -a ~/.aws/config
      echo "aws_secret_access_key=${var.AWS_SECRET_ACCESS_KEY}" | tee -a ~/.aws/config
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
      sudo apt-get update
      sudo apt-get install -y kubelet kubeadm kubectl
      sudo apt-mark hold kubelet kubeadm kubectl
      sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update && sudo apt-get install -y containerd.io
      sudo containerd config default | sudo tee /etc/containerd/config.toml
      sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
      sudo systemctl restart containerd
      sudo systemctl enable --now kubelet
      ################ INSTALAR AUTOCOMPLETE E ALIAS ######################
      kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
      echo 'alias k=kubectl' >>~/.bashrc
      echo 'complete -F __start_kubectl k' >>~/.bashrc
      #####################################################################
      JOIN_COMMAND=$(aws ssm get-parameter --name "k8s_join_command" --query "Parameter.Value" --with-decryption --output text)
      sudo $JOIN_COMMAND
      ################# INSTALANDO AS FERRAMENTAS QUE IREI UTILIZAR #######################
      if [ "$(hostname)" = "PICK-worker-1" ]; then
        mkdir ~/.kube
        aws ssm get-parameter --name "k8s_kubeconfig" --query "Parameter.Value" --with-decryption --output text > ~/.kube/config
        #Ingress Controller
        git clone https://github.com/FabioBartoli/LINUXtips-PICK.git
        kubectl apply --validate=false -f ./LINUXtips-PICK/main/modules/k8s_provisioner/ingress-deploy.yaml
        kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
        # Helm
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 get_helm.sh
        ./get_helm.sh
        # Adicionando repos ao Helm
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo add harbor https://helm.goharbor.io
        helm repo add kyverno https://kyverno.github.io/kyverno/
        helm repo update
        kubectl create ns harbor && kubectl create ns monitoring
        # Instalando o Harbor
        kubectl config set-context --current --namespace=harbor
        helm install harbor harbor/harbor --set expose.type=clusterIP --set expose.tls.auto.commonName=fabiobartoli.com.br --set persistence.enabled=false
        # Instalando o Kube-Prometheus
        kubectl config set-context --current --namespace=monitoring
        helm install kube-prometheus prometheus-community/kube-prometheus-stack
        # Instalando o Kyverno
        kubectl config set-context --current --namespace=default
        helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
        ###### Instalando os Ingress
        k apply -f ./LINUXtips-PICK/manifests/ingress/
        #### Locust
        sudo mkdir -p /usr/src/app/scripts/
        cat <<EOF2 | sudo tee /usr/src/app/scripts/locustfile.py
        from locust import HttpUser, task, between
        class Giropops(HttpUser):
            wait_time = between(1, 2)
            @task(1)
            def gerar_senha(self):
                self.client.post("/api/gerar-senha", json={"tamanho": 8, "incluir_numeros": True, "incluir_caracteres_especiais": True})
            @task(2)
            def listar_senha(self):
                self.client.get("/api/senhas")
        EOF2
        k apply -f LINUXtips-PICK/manifests/locust/
      fi
      EOF
    ]
    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ubuntu"
      private_key = var.private_key
    }
  }
  depends_on = [aws_instance.control_plane]
}
