provider "aws" {
    profile = "sandesh2000"
    region  = "ap-south-1"
}

resource "tls_private_key" "site_key" {
    algorithm   =   "RSA"
    rsa_bits    =   4096
}

resource "local_file" "private_key" {
    content         =   tls_private_key.site_key.private_key_pem
    filename        =   "my_key.pem"
    file_permission =   0400
}
resource "aws_key_pair" "site_key" {
    key_name   = "mykey"
    public_key = tls_private_key.site_key.public_key_openssh
}

resource "aws_security_group" "firewall_security" {
    name        = "secured"
    description = "https, ssh Protocols"
       ingress {
        description = "http-permit"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "ssh-permit"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
        egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "secured"
    }
}

resource "aws_instance" "myin" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.site_key.key_name
  security_groups = [ "secured" ]
depends_on = [
         aws_key_pair.site_key,
         aws_security_group.firewall_security,    
    ]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.site_key.private_key_pem
    host     = aws_instance.myin.public_ip
  }

provisioner "remote-exec" {
    inline = [
     "sudo yum install httpd php git -y",
     "sudo systemctl restart httpd",
     "sudo systemctl enable httpd",
     "sudo yum install amazon-efs-utils -y" ,
    ]
  }
 
 tags = {
     Name = "Divergent"
  }
}

resource "aws_efs_file_system" "efs" {
  depends_on = [
         aws_instance.myin,
      ]
  creation_token = "efs"

 tags = {
    Name = "efs"
  }
}
output "efs" {
   value = aws_efs_file_system.efs
}

resource "aws_efs_mount_target" "mount-efs" {
  depends_on = [
         aws_efs_file_system.efs,
      ]
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_instance.myin.subnet_id
  security_groups = ["${aws_security_group.firewall_security.id}"]
}

resource "null_resource" "nullremote3"  {
depends_on = [
    aws_efs_file_system.efs,
    aws_efs_mount_target.mount-efs
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.site_key.private_key_pem
    host     = aws_instance.myin.public_ip
  }
provisioner "remote-exec" {
    inline = [
        "efs_id=${aws_efs_file_system.efs.id} " ,
        "sudo mount -t efs $efs_id:/  /var/www/html",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/sandesh2000/multicloud-formation.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "jainsandesh2704" {
bucket= "jainsandesh2704"
acl  = "public-read"
force_destroy=true 
 tags = {
  Name="databucket"
 }
}

resource "aws_s3_bucket_object" "object1" {
  depends_on = [
      aws_s3_bucket.jainsandesh2704,
  ]  
  key    = "COVID_IMAGE"
bucket = aws_s3_bucket.jainsandesh2704.bucket
 acl = "public-read"
  source="C:\\Program Files\\Desktop\\covid.jpg"
  etag = filemd5("C:\\Program Files\\Desktop\\covid.jpg")
}
locals {
  s3_origin_id = "myS3"
}
resource "aws_cloudfront_distribution" "my_s3_distribution" {
  depends_on = [
           aws_s3_bucket.jainsandesh2704,
      ]
  origin {
    domain_name = aws_s3_bucket.jainsandesh2704.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
custom_origin_config {
    http_port = 80
    https_port = 80
    origin_protocol_policy = "match-viewer"
    origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"] 
    }
  }

enabled = true
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
forwarded_values {
    query_string = false
cookies {
      forward = "none"
      }
    }

viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
viewer_certificate {
    cloudfront_default_certificate = true
  }

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.site_key.private_key_pem
    host     = aws_instance.myin.public_ip
  }

provisioner "remote-exec" {
       inline = [    
   "sudo su << EOF",
   "echo \"<style>body{background-image:url('http://${self.domain_name}/${aws_s3_bucket_object.object1.key}');</style>\" >> /var/www/html/covid.html",
   "EOF" ,
   "sudo systemctl restart httpd", 
      ]        
  }
      
}

output  "instance_ip" {
	value = aws_instance.myin.public_ip
}


resource "null_resource" "null_local"  {


depends_on = [
    aws_cloudfront_distribution.my_s3_distribution,
  ]

provisioner "local-exec" {
command = "start chrome  ${aws_instance.myin.public_ip}/covid.html"
  }
}
