# Configures Terraform to use AWS in the us-east-1 region.
provider "aws" {
  region = "us-east-1"
}

# Creates a SageMaker model using the Llama Guard 3 container and prepackaged artifacts.
resource "aws_sagemaker_model" "llamaguard" {
  name               = "meta-llama-guard-3-8b"
  execution_role_arn = aws_iam_role.sagemaker_role.arn

  primary_container {
    # NOTE: this is a prebuilt container from AWS that is a Large Model Inference Container      
    # NOTE: here is the link to the large model containers: https://github.com/aws/deep-learning-containers/blob/master/available_images.md?utm_source=chatgpt.com 
    image = "763104351884.dkr.ecr.us-east-1.amazonaws.com/djl-inference:0.29.0-lmi11.0.0-cu124" 

    model_data_source {
      s3_data_source {
        # NOTE: this location is an AWS managed bucket that contains the prepackaged artifacts for the model.
        s3_uri           = "s3://jumpstart-private-cache-prod-us-east-1/meta-textgeneration/meta-textgeneration-llama-guard-3-8b/artifacts/inference-prepack/v1.0.0/"
        s3_data_type     = "S3Prefix"
        compression_type = "None"
        model_access_config {
          accept_eula = "true"
        }
      }
    }
    
    environment = {
      SAGEMAKER_MODEL_SERVER_TIMEOUT = "3600"
      HF_MODEL_ID                    = "/opt/ml/model"
      MODEL_CACHE_ROOT               = "/opt/ml/model"
      OPTION_ENABLE_CHUNKED_PREFILL     = "true"
      SAGEMAKER_ENV                  = "1"
      SAGEMAKER_MODEL_SERVER_WORKERS = "1"
      SAGEMAKER_PROGRAM              = "inference.py"
    }
  }
}

# Defines the endpoint configuration, specifying the model and instance type.
resource "aws_sagemaker_endpoint_configuration" "llamaguard_config" {
  name = "llamaguard3-config"

  production_variants {
    model_name             = aws_sagemaker_model.llamaguard.name
    variant_name           = "AllTraffic"
    initial_instance_count = 1
    instance_type          = "ml.g5.2xlarge"
  }
}

# Deploys a SageMaker endpoint for serving the model.
resource "aws_sagemaker_endpoint" "llamaguard_endpoint" {
  name                 = "llamaguard3-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.llamaguard_config.name
}

# Creates an IAM role for SageMaker with necessary permissions.
resource "aws_iam_role" "sagemaker_role" {
  name = "SageMakerExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# Defines a policy allowing SageMaker endpoint invocation.
resource "aws_iam_policy" "sagemaker_invoke_policy" {
  name        = "SageMakerInvokePolicy"
  description = "Policy to allow invoking the SageMaker endpoint"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sagemaker:InvokeEndpoint"
      Resource = aws_sagemaker_endpoint.llamaguard_endpoint.arn
    }]
  })
}

# Attaches the invocation policy to the SageMaker role.
resource "aws_iam_role_policy_attachment" "attach_sagemaker_policy" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = aws_iam_policy.sagemaker_invoke_policy.arn
}

# Grants SageMaker read-only access to Amazon ECR.
resource "aws_iam_role_policy_attachment" "attach_ecr_readonly" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Defines explicit permissions for SageMaker to pull images from ECR.
resource "aws_iam_policy" "ecr_access" {
  name        = "SageMakerECRAccess"
  description = "Allow SageMaker to pull images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "arn:aws:ecr:us-east-1:763104351884:repository/djl-inference"
      }
    ]
  })
}

# Attaches the ECR access policy to the SageMaker role.
resource "aws_iam_role_policy_attachment" "attach_ecr_policy" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = aws_iam_policy.ecr_access.arn
}