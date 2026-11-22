// Librenfra Email Worker: Email Routing'e gelen postayı tünel üzerinden mail makinesine iletir.
// Mail makinesi postayı Postfix'e verir ve Postfix'in yanıtını döner:
//   200 kabul, 550 kalıcı ret (gönderene geri çevrilir), diğerleri geçici hata.
export default {
  async email(message, env) {
    const response = await fetch(env.INBOUND_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.INBOUND_TOKEN}`,
        "X-Envelope-From": message.from,
        "X-Envelope-To": message.to,
        "Content-Type": "message/rfc822",
      },
      body: await new Response(message.raw).arrayBuffer(),
    });
    if (response.ok) return;
    const reason = (await response.text()).trim();
    if (response.status === 550) {
      message.setReject(reason);
      return;
    }
    // Atılan hata Email Routing'de geçici hata olarak kalır; gönderen sunucu yeniden dener.
    throw new Error(`mail makinesi yanıtı ${response.status}: ${reason}`);
  },
};
