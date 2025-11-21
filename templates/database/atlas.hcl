variable "envfile" {
  type    = string
  default = "../.env"
}

locals {
  // envfile = {
  //   for line in split("\n", file(var.envfile)) :
  //   trimspace(slice(split("=", line), 0, 1)[0]) => trimspace(join("=", slice(split("=", line), 1, length(split("=", line)))))
  //   if !startswith(trimspace(line), "#") && length(split("=", line)) > 1
  // }
  envfile = {
    for line in split("\n", file(var.envfile)) : split("=", line)[0] => regex("=(.*)", line)[0]
    if !startswith(line, "#") && length(split("=", line)) > 1
  }
}

env "main" {
  url = local.envfile["DB_ATLAS_URL"]
  src = "file://db/schema.sql"

  migration {
    dir    = "file://db/migrations"
    format = atlas
  }
} 