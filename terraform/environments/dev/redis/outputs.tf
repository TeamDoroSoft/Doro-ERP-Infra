output "redis_primary_endpoint" {
  description = "Store Access Redis hostname."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  description = "Store Access Redis TLS port."
  value       = aws_elasticache_replication_group.this.port
}

output "redis_security_group_id" {
  description = "Security group attached to the Redis replication group."
  value       = aws_security_group.redis.id
}

output "store_access_secret_values" {
  description = "Non-secret values to copy into doro-erp/dev/alpha/store-access."
  value = {
    STORE_ACCESS_REDIS_HOST        = aws_elasticache_replication_group.this.primary_endpoint_address
    STORE_ACCESS_REDIS_PORT        = tostring(aws_elasticache_replication_group.this.port)
    STORE_ACCESS_REDIS_SSL_ENABLED = "true"
  }
}
