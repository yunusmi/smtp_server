apt install openssl

PRIVATE_KEY="private.key"
PUBLIC_KEY="public.key"

DOMAIN=$DOMAIN_NAME

# Генерируем приватный ключ
openssl genrsa -out "$PRIVATE_KEY" 2048

# Создаем публичный ключ
openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"

# Генерируем DCIM подпись для домена
openssl dgst -sha256 -sign "$PRIVATE_KEY" -out "$DOMAIN_NAME".dcim "$DOMAIN_NAME"

echo "DCIM подпись для домена $DOMAIN_NAME была создана и сохранена в файле $DOMAIN_NAME.dcim"
