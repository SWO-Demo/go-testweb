output "jenkins_public_ip" {
  description = "Current public IP of Jenkins instance"
  value       = "Check jenkins.dedyn.io or EC2 console (IP changes on spot replacement)"
}

output "codebuild_project_name" {
  description = "CodeBuild project name to use in Jenkinsfiles"
  value       = aws_codebuild_project.jenkins_agent.name
}