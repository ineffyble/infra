resource "aws_kinesis_stream" "rabblerouser_stream" {
  name = "rabblerouser_stream"
  shard_count = 1
}

resource "aws_lambda_event_source_mapping" "stream_to_lambda" {
  event_source_arn = "${aws_kinesis_stream.rabblerouser_stream.arn}"
  function_name = "${aws_lambda_function.event_forwarder.arn}"
  starting_position = "LATEST"
}

data "aws_s3_bucket_object" "event_forwarder_zip" {
  bucket = "rabblerouser-artefacts"
  key = "lambdas/rabblerouser_event_forwarder.zip"
  # Defaults to latest version
}

resource "random_id" "rabblerouser_core_event_forwarder_auth_token" {
  keepers = {
    # Generate a new token when the lambda code updates or the EC2 instance changes
    lambda_zip_version = "${data.aws_s3_bucket_object.event_forwarder_zip.version_id}"
  }

  # With this length, it's as random as a type-4 UUID
  byte_length = 32
}

resource "aws_lambda_function" "event_forwarder" {
  s3_bucket = "${data.aws_s3_bucket_object.event_forwarder_zip.bucket}"
  s3_key = "${data.aws_s3_bucket_object.event_forwarder_zip.key}"
  s3_object_version = "${random_id.rabblerouser_core_event_forwarder_auth_token.keepers.lambda_zip_version}"
  function_name = "rabblerouser_event_forwarder"
  handler = "index.handler"
  role = "${aws_iam_role.event_forwarder_role.arn}"
  runtime = "nodejs4.3"
  environment = {
    variables = {
      EVENT_ENDPOINT = "https://${var.domain}/events"
      EVENT_AUTH_TOKEN = "${random_id.rabblerouser_core_event_forwarder_auth_token.hex}"
    }
  }
}

resource "aws_iam_role" "event_forwarder_role" {
  name = "event_forwarder_role"
  # This just dictates that only lambdas may assume this role
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "event_forwarder_policy" {
  role = "${aws_iam_role.event_forwarder_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}
