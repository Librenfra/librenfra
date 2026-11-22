#!/bin/bash
# mail makinesinin içinde çalışır. dc'de tests/mail/setup-dc.sh'nin açtığı kullanıcılar gerekir.
# Kullanım: ssh librenfra@mail sudo TEST_PHASE=<aşama> bash -s < tests/mail/test.sh
set -uo pipefail
pass=0 fail=0
check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}

# İstemci tarafı: SMTP ve IMAP, sunucunun sertifikası test CA'sıyla doğrulanarak.
mail_py() { python3 - "$@" <<'PY'
import imaplib, smtplib, ssl, sys, time, uuid
ctx = ssl.create_default_context(cafile="/etc/librenfra/ca.pem")
host = "mail.test.lan"
cmd, args = sys.argv[1], sys.argv[2:]

def message(env_from, hdr_from, rcpt, subject, extra=""):
    return (f"From: {hdr_from}\r\nTo: {rcpt}\r\nSubject: {subject}\r\n"
            f"Message-ID: <{uuid.uuid4()}@test>\r\n{extra}\r\ntest\r\n")

def main():
  if cmd == "submit":  # user password env_from hdr_from rcpt subject [Sender]
      user, pw, env_from, hdr_from, rcpt, subject = args[:6]
      extra = f"Sender: {args[6]}\r\n" if len(args) > 6 else ""
      with smtplib.SMTP(host, 587, timeout=120) as s:
          s.starttls(context=ctx)
          s.login(user, pw)
          s.sendmail(env_from, [rcpt], message(env_from, hdr_from, rcpt, subject, extra))
  elif cmd == "submit-noauth":  # env_from rcpt
      with smtplib.SMTP(host, 587, timeout=120) as s:
          s.starttls(context=ctx)
          s.sendmail(args[0], [args[1]], message(args[0], args[0], args[1], "parolasiz"))
  elif cmd == "rcpt25":  # rcpt: dışarıdan gelen posta gibi 25'e
      with smtplib.SMTP(host, 25, timeout=120) as s:
          s.ehlo("dis.test")
          s.starttls(context=ctx)
          s.ehlo("dis.test")
          s.mail("dis@dis.test")
          code, msg = s.rcpt(args[0])
          print(code, msg.decode())
          sys.exit(0 if code == 250 else 1)
  elif cmd == "deliver25":  # rcpt subject
      with smtplib.SMTP(host, 25, timeout=120) as s:
          s.ehlo("dis.test")
          s.starttls(context=ctx)
          s.sendmail("dis@dis.test", [args[0]], message("dis@dis.test", "dis@dis.test", args[0], args[1]))
  elif cmd == "imap":  # user password subject [wait-seconds]
      user, pw, subject = args[:3]
      deadline = time.time() + int(args[3] if len(args) > 3 else 120)
      while True:
          with imaplib.IMAP4_SSL(host, 993, ssl_context=ctx) as m:
              m.login(user, pw)
              typ, data = m.select("INBOX", readonly=True)
              if typ != "OK":
                  raise imaplib.IMAP4.error(f"INBOX açılamadı: {data}")
              typ, data = m.search(None, "SUBJECT", f'"{subject}"')
              if data[0].split():
                  sys.exit(0)
          if time.time() > deadline:
              print("posta gelmedi:", subject); sys.exit(1)
          time.sleep(5)
  elif cmd == "header":  # user password subject header: ilk eşleşen postanın başlığını yazar
      user, pw, subject, name = args[:4]
      with imaplib.IMAP4_SSL(host, 993, ssl_context=ctx) as m:
          m.login(user, pw)
          m.select("INBOX", readonly=True)
          typ, data = m.search(None, "SUBJECT", f'"{subject}"')
          num = data[0].split()[0]
          typ, data = m.fetch(num, f"(BODY.PEEK[HEADER.FIELDS ({name})])")
          print(data[0][1].decode().strip())
  elif cmd == "login":  # user password
      with imaplib.IMAP4_SSL(host, 993, ssl_context=ctx) as m:
          m.login(args[0], args[1])

try:
    main()
except (smtplib.SMTPException, imaplib.IMAP4.error) as e:
    print("REDDEDİLDİ:", e)
    sys.exit(1)
except Exception as e:
    print("HATA:", repr(e))
    sys.exit(2)
PY
}
export -f mail_py

ALI='Ali-Parola-2026!' AYSE='Ayse-Parola-2026!'
export ALI AYSE
run=$(date +%s)

# rejected <beklenen-yanıt> <mail_py argümanları...>: sunucu reddetmeli ve yanıtı uymalı.
# Bağlantı hatası ya da başka bir nedenle başarısızlık geçmiş sayılmaz.
rejected() {
    local want=$1; shift
    local out rc
    out=$(mail_py "$@" 2>&1); rc=$?
    echo "$out"
    [ "$rc" -eq 1 ] && grep -qE "$want" <<<"$out"
}

check "otomatik güncelleme kapalı (pipeline günceller)" sh -c "[ \"\$(systemctl is-enabled bootc-fetch-apply-updates.timer)\" = masked ]"
check "veri diski /var/vmail'e bağlı" bash -c "[ \"\$(findmnt -no SOURCE /var/vmail)\" = \"\$(readlink -f /dev/disk/by-id/virtio-lnfr-data)\" ]"
check "dizin bağlantısı hazır" systemctl is-active librenfra-mail-wait-dc.service
for s in postfix dovecot rspamd; do check "$s çalışıyor" systemctl is-active $s.service; done
check "Postfix ayarı geçerli" postfix check
check "dizin: alıcı bulunuyor" bash -c "[ \"\$(postmap -q ali@ornek.test ldap:/run/librenfra/postfix/recipients.cf)\" = ali ]"
check "dizin: devre dışı hesap alıcı değil" bash -c "! postmap -q ayse@ornek.test ldap:/run/librenfra/postfix/recipients.cf"

check "IMAP: dizin parolasıyla giriş" mail_py login ali "$ALI"
check "IMAP: yanlış parola reddedilir" rejected AUTHENTICATIONFAILED login ali yanlis
check "IMAP: devre dışı hesap giremez" rejected AUTHENTICATIONFAILED login ayse "$AYSE"

check "gönderim: kendi adresinden, kendine" mail_py submit ali "$ALI" ali@ornek.test ali@ornek.test ali@ornek.test "kendi-$run"
check "IMAP: gönderilen posta okunuyor" mail_py imap ali "$ALI" "kendi-$run"
check "DKIM: gönderilen posta alan adının anahtarıyla imzalı" bash -c "mail_py header ali \"\$ALI\" kendi-$run DKIM-Signature | tr -d ' \r\n\t' | grep -E 'd=ornek\.test;' | grep -q 's=librenfra;'"
check "gelen: dışarıdan 25'e teslim" mail_py deliver25 ali@ornek.test "dis-$run"
check "IMAP: dışarıdan gelen posta okunuyor" mail_py imap ali "$ALI" "dis-$run"
check "DKIM: dışarıdan gelen posta imzalanmaz" bash -c "out=\$(mail_py header ali \"\$ALI\" dis-$run DKIM-Signature) && ! grep -q DKIM <<<\"\$out\""
check "gelen: bilinmeyen alıcı reddedilir" rejected '^550 .*[Uu]ser unknown' rcpt25 yok@ornek.test
check "gelen: devre dışı hesaba posta yok" rejected '^550 .*[Uu]ser unknown' rcpt25 ayse@ornek.test
check "gelen: başka alana aktarım yok" rejected '^554 .*Relay access denied' rcpt25 biri@baska.test
check "gönderim: sahte zarf göndereni reddedilir" rejected '553.*not owned by user' submit ali "$ALI" ayse@ornek.test ayse@ornek.test ali@ornek.test "sahte-zarf-$run"
check "gönderim: sahte From: reddedilir" rejected 'hesaba ait degil' submit ali "$ALI" ali@ornek.test 'Rektor <rektor@ornek.test>' ali@ornek.test "sahte-from-$run"
check "gönderim: sahte Sender: reddedilir" rejected 'hesaba ait degil' submit ali "$ALI" ali@ornek.test ali@ornek.test ali@ornek.test "sahte-sender-$run" rektor@ornek.test
check "gönderim: boş zarf göndereni reddedilir" rejected '554.*<>' submit ali "$ALI" '' ali@ornek.test ali@ornek.test "bos-zarf-$run"
check "gönderim: parolasız gönderilemez" rejected '(530|554|Relay access denied|Client host rejected)' submit-noauth ali@ornek.test ali@ornek.test
# Cloudflare Email Worker'ın yolu: tünelden gelen HTTP isteği Postfix'e teslim edilir.
inbound() { # <token> <alıcı> <konu>: HTTP durum kodunu yazar
    printf 'From: dis@dis.test\r\nTo: %s\r\nSubject: %s\r\n\r\ntest\r\n' "$2" "$3" |
        curl -s -o /dev/null -w '%{http_code}' --data-binary @- -H "Authorization: Bearer $1" \
            -H 'X-Envelope-From: dis@dis.test' -H "X-Envelope-To: $2" http://127.0.0.1:8025/
}
export -f inbound
check "Cloudflare yolu: alıcı servisi çalışıyor" systemctl is-active librenfra-mail-inbound.service
check "Cloudflare yolu: posta teslim edilir" bash -c "[ \"\$(inbound test-inbound-token ali@ornek.test cf-$run)\" = 200 ]"
check "Cloudflare yolu: posta okunuyor" mail_py imap ali "$ALI" "cf-$run"
check "Cloudflare yolu: bilinmeyen alıcı 550" bash -c "[ \"\$(inbound test-inbound-token yok@ornek.test cf-yok)\" = 550 ]"
check "Cloudflare yolu: başka alana aktarım 550" bash -c "[ \"\$(inbound test-inbound-token biri@baska.test cf-baska)\" = 550 ]"
check "Cloudflare yolu: yanlış token 401" bash -c "[ \"\$(inbound yanlis ali@ornek.test cf-token)\" = 401 ]"
check "gelen: 127.0.0.1'den de aktarım yok" bash -c "python3 -c \"
import smtplib, sys
s = smtplib.SMTP('127.0.0.1', 25, timeout=60); s.ehlo('x'); s.mail('a@dis.test'); c, m = s.rcpt('b@baska.test'); print(c, m); sys.exit(0 if c == 554 else 1)\""
check "sahte postalar teslim edilmedi" rejected 'posta gelmedi' imap ali "$ALI" sahte- 0

# İlk kurulumda bırakılan posta, güncelleme, geri dönüş ve disk taşımadan sonra da okunur.
if [ "${TEST_PHASE:-}" = ilk ]; then
    check "kalıcı posta bırakıldı" mail_py submit ali "$ALI" ali@ornek.test ali@ornek.test ali@ornek.test kalici-posta
fi
check "kalıcı posta okunuyor" mail_py imap ali "$ALI" kalici-posta

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
