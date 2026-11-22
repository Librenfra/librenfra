// node --test infra/cloudflare/tests/email.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../worker/email.js";

const env = { INBOUND_URL: "https://mail-in.ornek.com/", INBOUND_TOKEN: "t" };
function message() {
  return {
    from: "dis@dis.test",
    to: "ali@ornek.com",
    raw: new Blob(["Subject: x\r\n\r\nx\r\n"]).stream(),
    rejected: null,
    setReject(reason) { this.rejected = reason; },
  };
}
function serve(status, text) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init, body: new TextDecoder().decode(init.body) });
    return new Response(text, { status });
  };
  return calls;
}

test("posta zarf ve token ile iletilir", async () => {
  const calls = serve(200, "kabul edildi");
  const m = message();
  await worker.email(m, env);
  assert.equal(calls[0].url, env.INBOUND_URL);
  assert.equal(calls[0].init.headers.Authorization, "Bearer t");
  assert.equal(calls[0].init.headers["X-Envelope-To"], "ali@ornek.com");
  assert.match(calls[0].body, /Subject: x/);
  assert.equal(m.rejected, null);
});

test("Postfix'in kalıcı reddi gönderene döner", async () => {
  serve(550, "550 5.1.1 <yok@ornek.com>: Recipient address rejected: User unknown\n");
  const m = message();
  await worker.email(m, env);
  assert.match(m.rejected, /User unknown/);
});

test("geçici hata reddedilmez, hata atılır", async () => {
  serve(451, "geçici hata");
  const m = message();
  await assert.rejects(worker.email(m, env), /451/);
  assert.equal(m.rejected, null);
});
