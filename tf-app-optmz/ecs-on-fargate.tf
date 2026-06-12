# # ALB Security Groups
# resource "aws_security_group" "alb" {
#   name_prefix = "gotest-alb-sg-"
#   description = "Allow HTTPS inbound from internet"
#   vpc_id      = data.aws_vpc.default.id

#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = { Name = "gotest-alb-sg" }
# }

# # ECS Security Groups
# resource "aws_security_group" "ecs" {
#   name_prefix = "gotest-ecs-sg-"
#   description = "Allow HTTP inbound from ALB only"
#   vpc_id      = data.aws_vpc.default.id

#   ingress {
#     from_port       = 80
#     to_port         = 80
#     protocol        = "tcp"
#     security_groups = [aws_security_group.alb.id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = { Name = "gotest-ecs-sg" }
# }

# # Application Load Balancer
# resource "aws_lb" "main" {
#   name               = "gotest-alb"
#   internal           = false
#   load_balancer_type = "application"
#   subnets            = var.subnet_ids
#   security_groups    = [aws_security_group.alb.id]

#   tags = { Name = "gotest-alb" }
# }

# resource "aws_lb_target_group" "app" {
#   name_prefix = "app-"
#   port        = 80
#   protocol    = "HTTP"
#   target_type = "ip"
#   vpc_id      = data.aws_vpc.default.id

#   health_check {
#     enabled             = true
#     path                = "/health"
#     matcher             = "200"
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 3
#     interval            = 30
#   }

#   tags = { Name = "gotest-tg" }
# }

# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = aws_acm_certificate.cert.arn

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }

# # IAM — ECS Task Execution Role
# resource "aws_iam_role" "ecs_task_execution" {
#   name = "gotest-ecs-task-execution-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Action    = "sts:AssumeRole"
#       Principal = { Service = "ecs-tasks.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
#   role       = aws_iam_role.ecs_task_execution.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # ECS Cluster
# resource "aws_ecs_cluster" "main" {
#   name = "gotest-fargate-cluster"
# }


# # ECS Task Definition
# resource "aws_ecs_task_definition" "app" {
#   family                   = "gotest-fargate-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn

#   container_definitions = jsonencode([{
#     name      = "gotest-app"
#     image     = "${aws_ecr_repository.gotest.repository_url}:v1.1"
#     essential = true

#     portMappings = [{
#       containerPort = 80
#       hostPort      = 80
#       protocol      = "tcp"
#     }]

#     healthCheck = {
#       command     = ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
#       interval    = 15
#       timeout     = 5
#       retries     = 3
#       startPeriod = 30
#     }
#   }])
# }

# # ECS Service
# resource "aws_ecs_service" "app" {
#   name            = "gotest-fargate-service"
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.app.arn
#   desired_count   = 1

#   capacity_provider_strategy {
#     capacity_provider = "FARGATE_SPOT"
#     weight            = 1
#   }

#   network_configuration {
#     subnets          = var.subnet_ids
#     security_groups  = [aws_security_group.ecs.id]
#     assign_public_ip = true
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.app.arn
#     container_name   = "gotest-app"
#     container_port   = 80
#   }

#   deployment_minimum_healthy_percent = 50
#   deployment_maximum_percent         = 200

#   depends_on = [aws_lb_listener.https]
# }
