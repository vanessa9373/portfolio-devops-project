output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name for the streaming platform"
  value       = aws_cloudfront_distribution.video.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidations)"
  value       = aws_cloudfront_distribution.video.id
}

output "raw_ingest_bucket" {
  description = "S3 bucket for uploading raw studio video files"
  value       = aws_s3_bucket.raw_ingest.id
}

output "processed_video_bucket" {
  description = "S3 bucket containing transcoded HLS segments served via CloudFront"
  value       = aws_s3_bucket.processed_video.id
}

output "mediaconvert_queue_arn" {
  description = "MediaConvert queue ARN for video transcoding jobs"
  value       = aws_media_convert_queue.main.arn
}

output "content_catalog_table" {
  description = "DynamoDB table name for content catalog and rendition status"
  value       = aws_dynamodb_table.content_catalog.name
}

output "user_entitlements_table" {
  description = "DynamoDB table name for user subscriptions and concurrent stream tracking"
  value       = aws_dynamodb_table.user_entitlements.name
}

output "ingest_orchestrator_function" {
  description = "Lambda function name for the video ingest orchestrator"
  value       = aws_lambda_function.ingest_orchestrator.function_name
}

output "cloudfront_key_group_id" {
  description = "CloudFront key group ID used for signed URL validation"
  value       = aws_cloudfront_key_group.signing.id
}

output "upload_command_example" {
  description = "Example AWS CLI command to upload a new title for transcoding"
  value       = "aws s3 cp my-movie.mp4 s3://${aws_s3_bucket.raw_ingest.id}/titles/TITLE_ID/source.mp4"
}
