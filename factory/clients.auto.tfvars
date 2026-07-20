# The one place you add a client or an app. Apply the factory to stamp workspaces.
#
# Each app lists the databases it connects to under `connections`:
#   { key = "<ConnectionStrings key>", db_name = "<db on the shared RDS>", migrate = <bool> }
# - key      -> the app reads it as ConnectionStrings__<key> (.NET).
# - db_name  -> a database on the client-env's shared RDS. Foundation creates the union of
#               every db_name referenced here (shared dbs are created once).
# - migrate  -> true = a db this app OWNS (EF Core migrates it). Usually one; can be several.
# - source   -> OPTIONAL. Set to another client-env's foundation workspace (e.g.
#               "ecolors-prod-foundation") when the db lives THERE (shared, cross-account). That
#               provider RDS is made public + allowlisted; the creds come via HCP remote state.
#               Absent = local db on this client-env's own RDS. Never migrate a `source` db.
organization   = "REPLACE_ORG"
oauth_token_id = "ot-REPLACE"
version_tag    = "v1.0.0"
aws_region     = "us-east-1"

clients = [
  {
    client      = "sayer"
    environment = "prod"
    zone_name   = "sayer.ecolors.app"
    apps = [
      {
        app     = "webapi"
        version = "1.0.0"
        connections = [
          { key = "Licensee", db_name = "EColorsSayerProd", migrate = true },
          # Shared Admin db lives in ecolors-prod (another account). `source` => cross-env read.
          { key = "Admin", db_name = "EColorsAdminProd", source = "ecolors-prod-foundation" },
        ]
        subdomain   = "api.sayer.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        settings = {
          "ASPNETCORE_ENVIRONMENT"         = "Production"
          "Serilog__MinimumLevel__Default" = "Information"
        }
        secret_settings = ["Jwt__SigningKey"]
      },
    ]
  },
  {
    client      = "ulbrika"
    environment = "prod"
    zone_name   = "ulbrika.ecolors.app"
    apps = [
      {
        app     = "webapi"
        version = "1.0.0"
        connections = [
          { key = "Licensee", db_name = "EColorsUlbrikaProd", migrate = true },
          { key = "Admin", db_name = "EColorsAdminProd", source = "ecolors-prod-foundation" },
        ]
        subdomain   = "api.ulbrika.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
      },
    ]
  },
  {
    client      = "ecolors"
    environment = "prod"
    zone_name   = "prod.ecolors.app"
    apps = [
      {
        app     = "admin-webapi"
        version = "1.0.0"
        connections = [
          { key = "Admin", db_name = "EColorsAdminProd", migrate = true },
        ]
        subdomain   = "admin.api.prod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
      },
      {
        app     = "authprovider-webapi"
        version = "1.0.0"
        connections = [
          { key = "AuthProvider", db_name = "EColorsAuthProviderProd", migrate = true },
          { key = "IdentityProvider", db_name = "EColorsIdentityProviderProd", migrate = true  },
        ]
        subdomain   = "authprovider.api.prod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-auth-provider-web-api"
      },
    ]
  },
  {
    client      = "ecolors"
    environment = "nonprod"
    zone_name   = "nonprod.ecolors.app"
    apps = [
      {
        app     = "admin-webapi"
        version = "1.0.0"
        connections = [
          { key = "Admin", db_name = "EColorsAdminDev", migrate = true },
        ]
        subdomain   = "admin.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
      },
      {
        app     = "seller-webapi"
        version = "1.0.0"
        connections = [
          { key = "Licensee", db_name = "EColorsSellerDev", migrate = true },
          { key = "Admin", db_name = "EColorsAdminDev" }, # shared admin db (owned by admin-webapi)
        ]
        subdomain   = "seller.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
      },
      {
        app     = "demo-webapi"
        version = "1.0.0"
        connections = [
          { key = "Licensee", db_name = "EColorsDemoDev", migrate = true },
          { key = "Admin", db_name = "EColorsAdminDev" }, # shared admin db (owned by admin-webapi)
        ]
        subdomain   = "demo.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
      },
      {
        app     = "authprovider-webapi"
        version = "1.0.0"
        connections = [
          { key = "AuthProvider", db_name = "EColorsAuthProviderDev", migrate = true },
          { key = "IdentityProvider", db_name = "EColorsIdentityProviderDev", migrate = true }, # CONFIRM owner (see prod)
        ]
        subdomain   = "authprovider.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-auth-provider-web-api"
      },
      {
        app     = "missingone-webapi"
        version = "1.0.0"
        connections = [
          { key = "Default", db_name = "MissingOneDev", migrate = true },
        ]
        subdomain   = "missingone.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/missingone-web-api"
      },
    ]
  },
]
