# راهنمای فارسی KavoshRust

KavoshRust برای نصب RustDesk Server OSS روی سرورهای Debian/Ubuntu طراحی شده است؛ به‌خصوص سروری که سرویس‌های دیگری روی آن فعال هستند.

در سرور فعلی Kavosh، معماری نصب این است:

```text
RustDesk OSS Native Binary
        +
systemd
        +
Nginx موجود سرور
        +
Certbot
```

Docker نصب نمی‌شود.

## نصب

ابتدا Preflight:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh) --preflight
```

سپس:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bagdeli/KavoshRust/main/install.sh)
```

و گزینه 1.

دامنه پیشنهادی پروژه:

```text
rust.kavosh.info
```

## پورت‌ها

اگر ID Port برابر P و Relay Port برابر R باشد:

```text
P-1/TCP
P/TCP
P/UDP
P+2/TCP
R/TCP
R+2/TCP
```

در حالت native همه این Listenerها روی Host ایجاد می‌شوند، بنابراین Installer قبل از نصب آزاد بودن همه آنها را بررسی می‌کند.

برای کلاینت دسکتاپ فقط این چهار Rule را در فایروال اینترنتی باز کنید:

```text
P-1/TCP
P/TCP
P/UDP
R/TCP
```

پورت‌های P+2 و R+2 مربوط به WebSocket هستند. اگر Web Client ندارید آنها را در فایروال Provider بسته نگه دارید.

## SSL

چون روی سرور فعلی Nginx روی 80/443 فعال است، KavoshRust Caddy یا Web Server دیگری اجرا نمی‌کند.

برای دامنه RustDesk یک vhost جدا می‌سازد، قبل از Reload دستور `nginx -t` را اجرا می‌کند و سپس با Certbot گواهی می‌گیرد.

اگر DNS درست نباشد یا Nginx validation خطا بدهد، RustDesk می‌تواند کار کند ولی SSL فعال نمی‌شود.

## مشخصات کلاینت

بعد از نصب:

```bash
kavoshrust --info
```

خروجی شامل:

```text
ID Server
Relay Server
Public Key
```

است.

هم Client تکنسین و هم Client مشتری باید همین مقادیر را داشته باشند. API Server در نسخه OSS خالی می‌ماند.

## مدل پشتیبانی مشتری

برای سناریوی Support:

```text
مشتری RustDesk را اجرا می‌کند
→ ID را اعلام می‌کند
→ تکنسین ID را وارد می‌کند
→ مشتری درخواست را Accept یا Reject می‌کند
```

برای این مدل، حالت تأیید دستی مشتری مناسب است.

## نگهداری

```bash
kavoshrust
kavoshrust --status
kavoshrust --info
kavoshrust --diagnostics
```

منو شامل Backup، Restore، Update، تغییر پورت، تغییر دامنه، SSL، Firewall، Logs، Force Relay و Uninstall است.

## امنیت

- SSH تغییر داده نمی‌شود.
- Docker نصب نمی‌شود.
- Nginx موجود جایگزین نمی‌شود.
- سرویس دیگر برای آزادکردن پورت Stop نمی‌شود.
- private key در GitHub قرار نمی‌گیرد.
- Backup شامل private key است و باید محرمانه نگهداری شود.
