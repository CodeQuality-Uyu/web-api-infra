# --- SSM bastion: private, no SSH key, no inbound. DB admin via port-forward. ---
data "aws_ssm_parameter" "al2023" {
  count = var.enable_bastion ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.bastion_arch}"
}

resource "aws_security_group" "bastion" {
  count       = var.enable_bastion ? 1 : 0
  name        = "${var.name}-bastion-sg"
  description = "SSM bastion; egress only"
  vpc_id      = aws_vpc.this.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-bastion-sg" })
}

data "aws_iam_policy_document" "bastion_assume" {
  count = var.enable_bastion ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  count              = var.enable_bastion ? 1 : 0
  name               = "${var.name}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count      = var.enable_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  count = var.enable_bastion ? 1 : 0
  name  = "${var.name}-bastion-profile"
  role  = aws_iam_role.bastion[0].name
}

resource "aws_instance" "bastion" {
  count                       = var.enable_bastion ? 1 : 0
  ami                         = data.aws_ssm_parameter.al2023[0].value
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  iam_instance_profile        = aws_iam_instance_profile.bastion[0].name
  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }
  tags = merge(var.tags, { Name = "${var.name}-bastion" })
}
