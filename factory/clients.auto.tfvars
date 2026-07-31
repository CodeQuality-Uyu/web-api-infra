# ============================================================================================
# La única fuente de verdad: quién existe, en qué cuenta AWS vive, y quién le habla a quién.
#
# Cada client-env tiene:
#   frontends -> SPAs.  Dominio derivado como "<name>.<zone_name>"; `serve_on_zone_root = true` lo
#                       pone en la zona misma (raíz). `calls` declara a qué backends le pega DESDE EL NAVEGADOR
#                       (incluí el authprovider: el login es browser-side) y de ahí sale el CORS.
#   backends  -> APIs.  `connections` declara a qué bases se conecta; `migrate = true` marca la
#                       base propia (la que migra EF Core).
#
# Todo lo que apunta a OTRO client-env usa:  source = { client = "...", environment = "..." }
# (puede estar en otra cuenta AWS, no hay problema).
# ============================================================================================
organization = "ColorLabs" # org de HCP Terraform
version_tag  = "v1.0.0"
# Todo se despliega en us-east-1 (fijo en el provider de cada stack; no es una variable).

# VCS: el oauth_token_id se resuelve solo desde la conexión VCS de la org (vcs_service_provider,
# default "github") — no hace falta pegar el "ot-XXXX". Con eso el factory conecta CADA workspace
# hijo al repo (branch = version_tag; el working directory ya lo fija por stack).
# Si usás conexión GitHub App (no OAuth), poné oauth_token_id explícito en su lugar.

# Cuentas y DNS se leen del remote state (no se hardcodean):
#   - management_workspace     -> ids de cuentas (vended + platform, incl. infrastructure)
#   - infrastructure_workspace -> parent_zone_id (default "infrastructure")
# La delegación DNS se auto-configura desde ahí. dns_parent_account_id / dns_parent_zone_id existen
# solo como override manual.
management_workspace = "management"

clients = [
  # ------------------------------------------------------------------ licenciatario: SAYER ---
  {
    client         = "sayer"
    environment    = "prod"
    zone_name      = "sayer.ecolors.app"

    frontends = [
      {
        name               = "web"
        version            = "1.0.0"
        serve_on_zone_root = true # https://sayer.ecolors.app
        bucket_name        = "sayer-prod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "webapi" },
          # El login va al authprovider de ECOLORS (otra cuenta).
          { backend = "authprovider-webapi", source = { client = "ecolors", environment = "prod" } },
        ]
      },
    ]

    backends = [
      {
        app     = "webapi"
        version = "1.0.0"
        # Los keys son los que el app lee con GetConnectionString(...): AdminConnection / LicenseeConnection.
        connections = [
          { key = "LicenseeConnection", db_name = "EColorsSayerProd", migrate = true },
          # La base Admin vive en ecolors-prod (otra cuenta): RDS público + allowlist.
          { key = "AdminConnection", db_name = "EColorsAdminProd", source = { client = "ecolors", environment = "prod" } },
        ]
        subdomain   = "api.sayer.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Licensee API (proyecto EColors.WebApi). Claves según su appsettings.json.
        settings = {
          "ASPNETCORE_ENVIRONMENT"          = "Production"
          "Authentication__Server"          = "https://authprovider.api.prod.ecolors.app"
          "Constants__LicenseeFrontendUrl"  = "https://sayer.ecolors.app"
          "Constants__AdminBackendApiUrl"   = "https://admin.api.prod.ecolors.app"
          "Constants__LicenseeTimeZoneCode" = "America/Mexico_City"
          "Constants__LicenseeId"           = "REPLACE_sayer_licensee_id"     # GUID del licenciatario (authprovider)
          "Constants__LicenseeAppId"        = "REPLACE_sayer_licensee_app_id" # GUID de la app del licenciatario
          "Constants__LicenseeRoleId"       = "REPLACE_licensee_role_id"
          "Constants__AdminRoleId"          = "REPLACE_admin_role_id"
          "Constants__CustomerRoleId"       = "REPLACE_customer_role_id"
          # Apps OAuth de plataforma (una sola de EColors para todos los licenciatarios).
          # El licensee las usa para armar la URL de "connect"; el access token por licenciatario
          # queda cifrado en la base (no acá).
          "MercadoPago__ClientId"           = "REPLACE_mp_client_id"
          "MercadoPago__IsSandbox"          = "false"
          "Stripe__ClientId"                = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey", # key del SDK de authprovider
          "Security__PaymentCryptoKey",     # descifra el token conectado del licenciatario
          "Resend__ApiKey",                 # mailing (Mailing__Type = Resend)
          "Geocoding__ApiKey",
          "MercadoPago__ClientSecret", # secret de la app OAuth de MercadoPago
          "Stripe__SecretKey",         # secret key de la app Stripe (plataforma)
        ]
        # Imágenes de producto (vía CDN) y Excels para descargar/procesar.
        # Dominio calculado: assets.sayer.ecolors.app.
        blobs = {}
      },
    ]
  },

  # ---------------------------------------------------------------- licenciatario: ULBRIKA ---
  {
    client         = "ulbrika"
    environment    = "prod"
    zone_name      = "ulbrika.ecolors.app"

    frontends = [
      {
        name               = "web"
        version            = "1.0.0"
        serve_on_zone_root = true # https://ulbrika.ecolors.app
        bucket_name        = "ulbrika-prod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "webapi" },
          { backend = "authprovider-webapi", source = { client = "ecolors", environment = "prod" } },
        ]
      },
    ]

    backends = [
      {
        app     = "webapi"
        version = "1.0.0"
        connections = [
          { key = "LicenseeConnection", db_name = "EColorsUlbrikaProd", migrate = true },
          { key = "AdminConnection", db_name = "EColorsAdminProd", source = { client = "ecolors", environment = "prod" } },
        ]
        subdomain   = "api.ulbrika.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Licensee API (proyecto EColors.WebApi).
        settings = {
          "ASPNETCORE_ENVIRONMENT"          = "Production"
          "Authentication__Server"          = "https://authprovider.api.prod.ecolors.app"
          "Constants__LicenseeFrontendUrl"  = "https://ulbrika.ecolors.app"
          "Constants__AdminBackendApiUrl"   = "https://admin.api.prod.ecolors.app"
          "Constants__LicenseeTimeZoneCode" = "America/Montevideo"
          "Constants__LicenseeId"           = "REPLACE_ulbrika_licensee_id"
          "Constants__LicenseeAppId"        = "REPLACE_ulbrika_licensee_app_id"
          "Constants__LicenseeRoleId"       = "REPLACE_licensee_role_id"
          "Constants__AdminRoleId"          = "REPLACE_admin_role_id"
          "Constants__CustomerRoleId"       = "REPLACE_customer_role_id"
          "MercadoPago__ClientId"           = "REPLACE_mp_client_id"
          "MercadoPago__IsSandbox"          = "false"
          "Stripe__ClientId"                = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey",
          "Security__PaymentCryptoKey",
          "Resend__ApiKey",
          "Geocoding__ApiKey",
          "MercadoPago__ClientSecret",
          "Stripe__SecretKey",
        ]
        # Imágenes de producto (vía CDN) y Excels para descargar/procesar.
        # Dominio calculado: assets.ulbrika.ecolors.app.
        blobs = {}
      },
    ]
  },

  # ------------------------------------------------------------- plataforma: ECOLORS (prod) ---
  {
    client         = "ecolors"
    environment    = "prod"
    zone_name      = "prod.ecolors.app"

    # Dominios derivados: admin.prod.ecolors.app y authprovider.prod.ecolors.app
    frontends = [
      {
        name        = "admin"
        version     = "1.0.0"
        bucket_name = "ecolors-admin-prod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "admin-webapi" },
          { backend = "authprovider-webapi" }, # login (mismo client-env)
        ]
      },
      {
        name        = "authprovider"
        version     = "1.0.0"
        bucket_name = "ecolors-authprovider-prod-web"
        github_repo = "CodeQuality-Uyu/auth-provider-react-web"
        calls       = [{ backend = "authprovider-webapi" }] # es la UI de login
      },
    ]

    backends = [
      {
        app     = "admin-webapi"
        version = "1.0.0"
        connections = [
          { key = "AdminConnection", db_name = "EColorsAdminProd", migrate = true },
        ]
        subdomain   = "admin.api.prod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Admin API (proyecto EColors.AdminWebApi). IsLicenseeApi=false viene del build.
        settings = {
          "ASPNETCORE_ENVIRONMENT"        = "Production"
          "Authentication__Server"        = "https://authprovider.api.prod.ecolors.app"
          "Constants__AdminBackendApiUrl" = "https://admin.api.prod.ecolors.app"
          # El admin hace el canje OAuth code->token y valida webhooks de los proveedores de pago.
          "MercadoPago__ClientId"         = "REPLACE_mp_client_id"
          "MercadoPago__OAuthApi"         = "https://api.mercadopago.com/oauth/token"
          "MercadoPago__OAuthRedirectUri" = "https://admin.api.prod.ecolors.app/mercado-pago/connect/callback"
          "MercadoPago__IsSandbox"        = "false"
          "Stripe__ClientId"              = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey",
          "Security__PaymentCryptoKey", # cifra el token conectado al guardarlo en el callback
          "MercadoPago__ClientSecret",
          "MercadoPago__WebhookSecret",
          "Stripe__SecretKey",
          "Stripe__WebhookSecret",
        ]
      },
      {
        app     = "authprovider-webapi"
        version = "1.0.0"
        connections = [
          { key = "AuthProvider", db_name = "EColorsAuthProviderProd", migrate = true },
          { key = "IdentityProvider", db_name = "EColorsIdentityProviderProd", migrate = true },
        ]
        subdomain   = "authprovider.api.prod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-auth-provider-web-api"
      },
    ]
  },

  # ---------------------------------------------------------- plataforma: ECOLORS (nonprod) ---
  {
    client      = "ecolors"
    environment = "nonprod"
    zone_name   = "nonprod.ecolors.app"
    # nonprod (dev/qa): App Runner más chico para ahorrar (0.5 vCPU / 1 GB).
    service_cpu    = "512"
    service_memory = "1024"
    # Pausar en la madrugada (02:00–07:00, hora local). App Runner no cobra mientras está pausado.
    service_pause = {} # usa los defaults: pausa 02:00, reanuda 07:00, America/Montevideo

    # Cuatro FEs, uno por backend. missingone-webapi no tiene FE.
    frontends = [
      {
        name        = "admin"
        version     = "1.0.0"
        bucket_name = "ecolors-admin-nonprod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "admin-webapi" },
          { backend = "authprovider-webapi" },
        ]
      },
      {
        name        = "seller"
        version     = "1.0.0"
        bucket_name = "ecolors-seller-nonprod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "seller-webapi" },
          { backend = "authprovider-webapi" },
        ]
      },
      {
        name        = "demo"
        version     = "1.0.0"
        bucket_name = "ecolors-demo-nonprod-web"
        github_repo = "CodeQuality-Uyu/ecolors-react-web"
        calls = [
          { backend = "demo-webapi" },
          { backend = "authprovider-webapi" },
        ]
      },
      {
        name        = "authprovider"
        version     = "1.0.0"
        bucket_name = "ecolors-authprovider-nonprod-web"
        github_repo = "CodeQuality-Uyu/auth-provider-react-web"
        calls       = [{ backend = "authprovider-webapi" }]
      },
    ]

    backends = [
      {
        app     = "admin-webapi"
        version = "1.0.0"
        connections = [
          { key = "AdminConnection", db_name = "EColorsAdminDev", migrate = true },
        ]
        subdomain   = "admin.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Admin API (proyecto EColors.AdminWebApi).
        settings = {
          "ASPNETCORE_ENVIRONMENT"        = "Production"
          "Authentication__Server"        = "https://authprovider.api.nonprod.ecolors.app"
          "Constants__AdminBackendApiUrl" = "https://admin.api.nonprod.ecolors.app"
          "MercadoPago__ClientId"         = "REPLACE_mp_client_id"
          "MercadoPago__OAuthApi"         = "https://api.mercadopago.com/oauth/token"
          "MercadoPago__OAuthRedirectUri" = "https://admin.api.nonprod.ecolors.app/mercado-pago/connect/callback"
          "MercadoPago__IsSandbox"        = "true"
          "Stripe__ClientId"              = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey",
          "Security__PaymentCryptoKey",
          "MercadoPago__ClientSecret",
          "MercadoPago__WebhookSecret",
          "Stripe__SecretKey",
          "Stripe__WebhookSecret",
          "Resend__ApiKey",
        ]
      },
      {
        app     = "seller-webapi"
        version = "1.0.0"
        connections = [
          { key = "LicenseeConnection", db_name = "EColorsSellerDev", migrate = true },
          { key = "AdminConnection", db_name = "EColorsAdminDev" }, # base admin compartida (dueño: admin-webapi)
        ]
        subdomain   = "seller.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Licensee API (proyecto EColors.WebApi).
        settings = {
          "ASPNETCORE_ENVIRONMENT"          = "Production"
          "Authentication__Server"          = "https://authprovider.api.nonprod.ecolors.app"
          "Constants__LicenseeFrontendUrl"  = "https://seller.nonprod.ecolors.app"
          "Constants__AdminBackendApiUrl"   = "https://admin.api.nonprod.ecolors.app"
          "Constants__LicenseeTimeZoneCode" = "America/Mexico_City"
          "Constants__LicenseeId"           = "REPLACE_seller_licensee_id"
          "Constants__LicenseeAppId"        = "REPLACE_seller_licensee_app_id"
          "Constants__LicenseeRoleId"       = "REPLACE_licensee_role_id"
          "Constants__AdminRoleId"          = "REPLACE_admin_role_id"
          "Constants__CustomerRoleId"       = "REPLACE_customer_role_id"
          "MercadoPago__ClientId"           = "REPLACE_mp_client_id"
          "MercadoPago__IsSandbox"          = "true"
          "Stripe__ClientId"                = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey",
          "Security__PaymentCryptoKey",
          "Resend__ApiKey",
          "Geocoding__ApiKey",
          "MercadoPago__ClientSecret",
          "Stripe__SecretKey",
        ]
      },
      {
        app     = "demo-webapi"
        version = "1.0.0"
        connections = [
          { key = "LicenseeConnection", db_name = "EColorsDemoDev", migrate = true },
          { key = "AdminConnection", db_name = "EColorsAdminDev" },
        ]
        subdomain   = "demo.api.nonprod.ecolors.app"
        github_repo = "CodeQuality-Uyu/ecolors-web-api"
        # Licensee API (proyecto EColors.WebApi).
        settings = {
          "ASPNETCORE_ENVIRONMENT"          = "Production"
          "Authentication__Server"          = "https://authprovider.api.nonprod.ecolors.app"
          "Constants__LicenseeFrontendUrl"  = "https://demo.nonprod.ecolors.app"
          "Constants__AdminBackendApiUrl"   = "https://admin.api.nonprod.ecolors.app"
          "Constants__LicenseeTimeZoneCode" = "America/Mexico_City"
          "Constants__LicenseeId"           = "REPLACE_demo_licensee_id"
          "Constants__LicenseeAppId"        = "REPLACE_demo_licensee_app_id"
          "Constants__LicenseeRoleId"       = "REPLACE_licensee_role_id"
          "Constants__AdminRoleId"          = "REPLACE_admin_role_id"
          "Constants__CustomerRoleId"       = "REPLACE_customer_role_id"
          "MercadoPago__ClientId"           = "REPLACE_mp_client_id"
          "MercadoPago__IsSandbox"          = "true"
          "Stripe__ClientId"                = "REPLACE_stripe_client_id"
        }
        secret_settings = [
          "Authentication__SuscriptionKey",
          "Security__PaymentCryptoKey",
          "Resend__ApiKey",
          "Geocoding__ApiKey",
          "MercadoPago__ClientSecret",
          "Stripe__SecretKey",
        ]
      },
      {
        app     = "authprovider-webapi"
        version = "1.0.0"
        connections = [
          { key = "AuthProvider", db_name = "EColorsAuthProviderDev", migrate = true },
          { key = "IdentityProvider", db_name = "EColorsIdentityProviderDev", migrate = true },
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
