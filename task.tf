provider "aws" {
        region  = "ap-south-1"
	access_key = "AKIAZIC7FGF2XNTOFB47"
        secret_key = "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"
}

resource "tls_private_key" "key" {
  algorithm   = "RSA"
}

resource "aws_key_pair" "mykey" {
  key_name   = "mykey11222" 
  public_key = tls_private_key.key.public_key_openssh
}

resource "local_file" "key-file" {
  	content  = tls_private_key.key.private_key_pem
  	filename = "key.pem"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  instance_tenancy = "default"
  
  tags = {
	name = "myvpc"
	}
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.vpc.id
  availability_zone = "ap-south-1b"
  cidr_block = "10.1.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "mysubnet"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "gateway"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "route"
  }
}

resource "aws_route_table_association" "route_association" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_security_group" "security_group" {
  name        = "security"
  description = "sec group for ssh and httpd"
  vpc_id      = aws_vpc.vpc.id

    ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "security"
  }
}

resource "aws_instance"  "my_instance"  {
 	ami = "ami-0447a12f28fddb066" 
  	instance_type = "t2.micro"
  	key_name = aws_key_pair.mykey.key_name
  	security_groups = [ aws_security_group.security_group.id ]
        availability_zone = "ap-south-1b"
	subnet_id = aws_subnet.subnet.id
   tags = {
    	  Name = "myos" 
  	}
        
	
}

resource "aws_efs_file_system" "efs" {
  creation_token = "efs"
  performance_mode = "generalPurpose"

  tags = {
    Name = "myefs"
  }
}

resource "aws_efs_mount_target" "mount_target" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.subnet.id
  security_groups = [ aws_security_group.security_group.id ]
}

resource "null_resource" "mount_efs_volume" {


	connection {
  	  type     = "ssh"
   	  user     = "ec2-user"
   	  private_key = tls_private_key.key.private_key_pem 
   	  host = aws_instance.my_instance.public_ip
  }

 	provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      "sudo setenforce 0",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo echo 'aws_efs_file_system.efs.id:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo mount aws_efs_file_system.efs.id:/ /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Ashutosh2001/AWS_task_2.git /var/www/html/"
	]
  }
}

resource "aws_s3_bucket" "s3_bucket" {
  bucket = "ashubucket2001564"
  acl    = "private"
 tags = {
    Name = "bucket"
  }
 
}

resource "aws_s3_bucket_public_access_block" "access_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "bucket_object" {
  for_each		 = fileset("C:/Users/ASHU/Desktop/Terra/task_2/pic", "**/*.jpg")
  bucket                 = aws_s3_bucket.s3_bucket.bucket
  key                    = each.value
  source                 = "C:/Users/ASHU/Desktop/Terra/task_2/pic/${each.value}"
  content_type 		 = "image/jpg"

}

locals {
	s3_origin_id = "myorigin"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
	comment = "s3_bucket"
}

resource "aws_cloudfront_distribution" "cloud_distribution" {
  depends_on= [aws_s3_bucket.s3_bucket]
  origin {
        domain_name = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
        origin_id = local.s3_origin_id

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
	# By default, show index.html file:
    	default_root_object = "AWS_PHP.php"
    	enabled = true

    	# If there is a 404, return AWS_PHP.php with a HTTP 200 Response:
    	custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/AWS_PHP.php"
    }

    	default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id

        #Not Forward all query strings, cookies and headers:
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    	# Distributes content to all:
    	price_class = "PriceClass_All"

    	# Restricts who is able to access this content:
    	restrictions {
        geo_restriction {
        # type of restriction, blacklist, whitelist or none:
        restriction_type = "none"
        }
    }

    	# SSL certificate for the service:
    	viewer_certificate {
        cloudfront_default_certificate = true
    }
}

#OUTPUT:
output "cloudfront_ip_addr" {
  	value = aws_cloudfront_distribution.cloud_distribution.domain_name
}