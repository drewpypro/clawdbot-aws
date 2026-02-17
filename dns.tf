# Just for informational purpose if you want to create DNS entries
# variable "cloudflare_zone_id" {
#   type = string
# }

# variable "cloudflare_account_id" {
#   type = string
# }

# locals {
#   ddns_cnames_proxy = [
#     "subdomain1.yourdomain.com",
#     "subdomain2.yourdomain.com",
#   ]
# }

# resource "cloudflare_dns_record" "ddns_cnames" {
#   for_each = toset(local.ddns_cnames_proxy)

#   zone_id = var.cloudflare_zone_id
#   name    = each.value
#   type    = "CNAME"
#   content = "ddns.yourdomain.com"
#   comment = "Built via TF Pipeline"
#   ttl     = 1
#   proxied = true
# }

