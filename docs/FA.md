# راهنمای فارسی KavoshRust

KavoshRust برای نصب و نگهداری RustDesk Server OSS روی Debian/Ubuntu طراحی شده است؛ مخصوصاً برای سروری که سرویس‌های دیگری هم روی آن فعال هستند و نباید با نصب RustDesk مختل شوند.

## نصب سریع

ابتدا فقط وضعیت سرور را بدون اعمال تغییر بررسی کنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

سپس Installer را اجرا کنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

گزینه زیر را انتخاب کنید:

```text
1) Install / Repair RustDesk OSS
```

اسکریپت دامنه، ID Port و Relay Port را می‌پرسد. پورت‌های پیش‌فرض RustDesk پذیرفته نمی‌شوند. کل بازه پورت قابل انتخاب است؛ پورت‌های پایین‌تر از 1024 نیز قابل انتخاب‌اند ولی به‌عنوان پورت‌های حساس/معروف هشدار می‌گیرند.

پس از نصب، منو با این فرمان در دسترس است:

```bash
kavoshrust
```

## انتخاب پورت

RustDesk بعضی پورت‌ها را از پورت اصلی محاسبه می‌کند. اگر ID Port را `P` و Relay Port را `R` انتخاب کنید:

```text
P-1/TCP  NAT test
P/TCP    ID / rendezvous
P/UDP    registration / heartbeat
P+2/TCP  hbbs WebSocket (اختیاری)

R/TCP    Relay
R+2/TCP  hbbr WebSocket (اختیاری)
```

بنابراین ID Port و Relay Port آزادانه انتخاب می‌شوند، ولی پورت‌های وابسته باید مطابق رفتار خود RustDesk باشند. به دلیل `P-1` و `P+2`، مقدار ID Port باید بین `2..65533` باشد و Relay Port بین `1..65533`. Installer همه پورت‌هایی را که قرار است روی Host منتشر شوند بررسی می‌کند و در صورت اشغال بودن، نصب را روی آن پورت انجام نمی‌دهد.

WebSocketها به‌صورت پیش‌فرض منتشر نمی‌شوند.

## دامنه و SSL

برای نمونه:

```text
rust.kavosh.info
```

باید A Record به IP عمومی سرور اشاره کند.

اگر 80/443 آزاد باشند، Caddy به‌صورت خودکار HTTPS و تمدید گواهی را مدیریت می‌کند. اگر این پورت‌ها توسط سرویس دیگری اشغال باشند، KavoshRust آن سرویس را متوقف نمی‌کند و RustDesk بدون Caddy نصب می‌شود.

HTTPS مربوط به Health/Landing endpoint است؛ ترافیک Native خود RustDesk روی پورت‌های انتخابی اجرا می‌شود.

## دریافت مشخصات کلاینت

بعد از نصب:

```bash
kavoshrust
```

سپس گزینه 3 را انتخاب کنید. خروجی شامل این موارد است:

```text
ID Server
Relay Server
Public Key
```

در هر دو Client تکنسین و مشتری، همین مقادیر را در:

```text
Settings -> Network -> Unlock Network Settings
```

وارد کنید.

برای پشتیبانی موردی بهتر است سمت مشتری تأیید دستی فعال باشد:

```text
approve-mode=click
```

در این حالت مشتری ID را اعلام می‌کند، تکنسین درخواست اتصال می‌دهد و مشتری با Accept اجازه می‌دهد.

## سرور Router / VPN

اگر `net.ipv4.ip_forward=1` باشد و Docker از قبل نصب نباشد، Installer قبل از نصب Docker مسیرها و Policy Ruleها را نشان می‌دهد و بدون تأیید صریح ادامه نمی‌دهد. دلیل این رفتار این است که Docker ممکن است روی iptables/FORWARD تغییر ایجاد کند. اگر در این مرحله Cancel کنید، Docker و RustDesk نصب نمی‌شوند.

## امنیت روی سرور مشترک

Installer:

- SSH را تغییر نمی‌دهد.
- سرویس دیگری را برای آزادکردن پورت Stop/Kill نمی‌کند.
- UFW/firewalld را در صورت غیرفعال بودن خودکار فعال نمی‌کند.
- اگر 80/443 اشغال باشند، سرویس فعلی را جایگزین نمی‌کند.
- private key را در GitHub قرار نمی‌دهد.
- پورت‌های WebSocket را مگر با درخواست صریح منتشر نمی‌کند.

## دستورات مفید

```bash
kavoshrust --preflight
kavoshrust --status
kavoshrust --info
kavoshrust --diagnostics
```

برای جزئیات بیشتر فایل‌های `CLIENT.md`، `SERVER.md`، `SECURITY.md`، `MAINTENANCE.md` و `TROUBLESHOOTING.md` را ببینید.
