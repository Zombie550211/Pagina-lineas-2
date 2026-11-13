#!/usr/bin/env bash
# Publica tumovilplan.com en S3 e invalida CloudFront.
#   BUCKET=... DIST=... ./infra/deploy.sh
set -euo pipefail
REGION="us-east-1"
BUCKET="${BUCKET:?falta BUCKET}"
DIST="${DIST:?falta DIST}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> Ensamblando dist/ (solo lo publico)"
rm -rf dist && mkdir -p dist
cp index.html privacidad.html terminos.html robots.txt sitemap.xml favicon.ico dist/
cp -r images dist/images

# index2.html es la variante descartada; instruction.txt es material interno.
for prohibido in index2.html instruction.txt .claude .vscode infra .git; do
  if [ -e "dist/$prohibido" ]; then echo "ABORTADO: dist/$prohibido no debe publicarse"; exit 1; fi
done

echo "==> Subiendo imagenes (cache larga)"
aws s3 sync dist/ "s3://$BUCKET/" --region "$REGION" --delete \
  --exclude "*.html" --exclude "robots.txt" --exclude "sitemap.xml" \
  --cache-control "public, max-age=31536000, immutable" --only-show-errors

echo "==> Subiendo HTML (sin cache en navegador)"
aws s3 sync dist/ "s3://$BUCKET/" --region "$REGION" \
  --exclude "*" --include "*.html" --include "robots.txt" --include "sitemap.xml" \
  --cache-control "public, max-age=0, must-revalidate" --only-show-errors

echo "==> URLs limpias (/privacidad, /terminos)"
for p in privacidad terminos; do
  aws s3 cp "dist/$p.html" "s3://$BUCKET/$p" --region "$REGION" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "public, max-age=0, must-revalidate" --only-show-errors
done

echo "==> Invalidando CloudFront ($DIST)"
ID=$(aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" --query 'Invalidation.Id' --output text)
aws cloudfront wait invalidation-completed --distribution-id "$DIST" --id "$ID"
echo "==> Listo. https://tumovilplan.com"
