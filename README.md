# SistemasClinicos PoC - AWS Terraform Infrastructure

Este proyecto despliega una infraestructura completa en AWS para el PoC de SistemasClinicos, con acceso privado a través de VPN.

## 🏗️ Arquitectura

La infraestructura incluye:

- **VPC privada** con subredes en múltiples AZs
- **AWS Client VPN** para acceso seguro
- **Application Load Balancer (ALB)** interno con WAF
- **EC2 Ubuntu** con servidor web Apache
- **Aurora MySQL** cluster en subredes privadas
- **WAF** para protección y detección de VPN
- **S3** con página estática para usuarios sin VPN

## 🔐 Características de Seguridad

- ✅ Todos los recursos en subredes privadas
- ✅ Acceso únicamente a través de VPN
- ✅ WAF con reglas de protección
- ✅ Security Groups restrictivos
- ✅ Certificados TLS autofirmados para VPN
- ✅ Contraseñas almacenadas en Secrets Manager

## 📋 Requisitos Previos

1. **AWS CLI** configurado con credenciales apropiadas
2. **Terraform** v1.0 o superior
3. **OpenVPN client** para conectarse a la VPN
4. **Key Pair** de EC2 (especificar en variables)

## 🚀 Despliegue

### 1. Clonar y preparar

```bash
cd terraform-poc-sistemasclinicos
```

### 2. Configurar variables

Edite `terraform.tfvars` (crear si no existe):

```hcl
aws_region         = "us-east-1"
environment        = "poc"
availability_zones = ["us-east-1a", "us-east-1b"]
key_pair_name      = "mi-keypair"  # Cambiar por su key pair existente
```

### 3. Inicializar y desplegar

```bash
# Inicializar Terraform
terraform init

# Revisar el plan
terraform plan

# Aplicar la configuración
terraform apply
```

## 🔑 Configuración de VPN

### 1. Generar certificados cliente

Después del despliegue, necesitará generar certificados para los clientes:

```bash
# Obtener la configuración del cliente VPN
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) \
  --output text > client-config.ovpn
```

### 2. Generar certificado de cliente

```bash
# Crear certificado de cliente (ejecutar en máquina local)
# Este script debe ejecutarse donde tenga acceso a las claves privadas generadas por Terraform

# Obtener la clave privada del certificado cliente desde Terraform state
terraform show -json | jq -r '.values.root_module.resources[] | select(.address=="tls_private_key.client") | .values.private_key_pem' > client.key

# Crear certificado de cliente firmado por el CA
openssl genrsa -out client1.key 2048
openssl req -new -key client1.key -out client1.csr -subj "/CN=client1"
openssl x509 -req -in client1.csr -CA client-ca.crt -CAkey client.key -CAcreateserial -out client1.crt -days 365

# Agregar certificados al archivo de configuración
echo "<cert>" >> client-config.ovpn
cat client1.crt >> client-config.ovpn
echo "</cert>" >> client-config.ovpn
echo "<key>" >> client-config.ovpn
cat client1.key >> client-config.ovpn
echo "</key>" >> client-config.ovpn
```

### 3. Instalar y configurar OpenVPN

1. Descargar [OpenVPN Client](https://openvpn.net/client-connect-vpn-for-windows/)
2. Importar el archivo `client-config.ovpn`
3. Conectarse a la VPN

## 🌐 Acceso a la Aplicación

### Con VPN conectada:
- Acceder al ALB interno: `http://<alb-dns-name>`
- Verá la página principal de SistemasClinicos

### Sin VPN:
- Será redirigido a una página que indica la necesidad de VPN

## 📊 Outputs Importantes

```bash
# Obtener información importante
terraform output vpc_id
terraform output vpn_endpoint_dns_name
terraform output alb_dns_name
terraform output aurora_cluster_endpoint
terraform output ec2_private_ip
```

## 🗄️ Base de Datos

### Conexión a Aurora MySQL

```bash
# Obtener credenciales de Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_password_secret_id) \
  --query SecretString --output text | jq .

# Conectar desde EC2 instance (vía SSH túnel a través de VPN)
mysql -h $(terraform output -raw aurora_cluster_endpoint) \
  -u admin -p sistemasclinicos
```

## 🏷️ Tags

Todos los recursos incluyen el tag requerido:
- `PoC SistemasClinicos` = `true`
- `Project` = `SistemasClinicos`
- `ManagedBy` = `Terraform`
- `Environment` = `poc`

## 🧹 Limpieza

Para eliminar toda la infraestructura:

```bash
terraform destroy
```

## 📝 Notas Importantes

1. **Costos**: Esta infraestructura genera costos en AWS (VPN, Aurora, NAT Gateway, etc.)
2. **Certificados**: Los certificados TLS son autofirmados para el PoC
3. **Producción**: Para producción, usar certificados de CA válidos
4. **Backup**: Aurora está configurado con backup de 7 días
5. **Monitoreo**: CloudWatch logs habilitados para VPN

## 🔧 Troubleshooting

### VPN no conecta
- Verificar que los certificados estén correctamente configurados
- Revisar logs en CloudWatch: `/aws/clientvpn/poc-sistemasclinicos`

### ALB no responde
- Verificar que esté conectado a la VPN
- Comprobar Security Groups
- Revisar WAF rules en AWS Console

### Aurora no accesible
- Verificar Security Groups
- Confirmar que está en la misma VPC
- Revisar subnet groups

## 📞 Soporte

Para soporte técnico, contactar al administrador de sistemas con:
- Logs de CloudWatch
- Outputs de Terraform
- Descripción del problema