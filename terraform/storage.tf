resource "aws_s3_bucket" "minecraft" {
  bucket = "${var.project_name}"
}

resource "aws_s3_bucket_versioning" "minecraft" {
  bucket = aws_s3_bucket.minecraft.id

  versioning_configuration {
    status = "Enabled"
  }
}