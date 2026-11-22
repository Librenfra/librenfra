#!/usr/bin/env python3
"""Firewall testinin ağ yardımcıları; segment ad alanlarının içinde çalışır.

  net.py listen <adres> <proto:port>...   verilen portlarda dinler, gelen her bağlantıya "ok" der
  net.py probe <tcp|udp> <adres> <port>   bağlantı kurulup yanıt gelirse 0 ile çıkar
  net.py dhcp <arayüz>                    DHCPDISCOVER gönderir, önerilen adresi yazar
"""
import os
import random
import socket
import struct
import sys
import threading


def listen(addr, specs):
    def tcp(port):
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((addr, port))
        s.listen()
        while True:
            c, _ = s.accept()
            try:
                c.sendall(b"ok\n")
            finally:
                c.close()

    def udp(port):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind((addr, port))
        while True:
            _, peer = s.recvfrom(2048)
            s.sendto(b"ok\n", peer)

    threads = []
    for spec in specs:
        proto, port = spec.split(":")
        t = threading.Thread(target={"tcp": tcp, "udp": udp}[proto], args=(int(port),), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()


def probe(proto, addr, port):
    if proto == "tcp":
        s = socket.create_connection((addr, int(port)), timeout=5)
        data = s.recv(16)
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(5)
        s.sendto(b"ping\n", (addr, int(port)))
        data, _ = s.recvfrom(16)
    sys.exit(0 if data.startswith(b"ok") else 1)


def dhcp(ifname):
    with open(f"/sys/class/net/{ifname}/address") as f:
        mac = bytes.fromhex(f.read().strip().replace(":", ""))
    xid = random.getrandbits(32)
    pkt = struct.pack("!BBBBIHH4s4s4s4s16s64s128s", 1, 1, 6, 0, xid, 0, 0x8000, b"\0" * 4, b"\0" * 4,
                      b"\0" * 4, b"\0" * 4, mac.ljust(16, b"\0"), b"\0" * 64, b"\0" * 128)
    pkt += b"\x63\x82\x53\x63" + b"\x35\x01\x01" + b"\xff"
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, ifname.encode())
    s.bind(("0.0.0.0", 68))
    # dnsmasq bir adresi önermeden önce ona ping atar; yavaş bir makinede yanıt birkaç saniye sürer.
    s.settimeout(10)
    for _ in range(4):
        s.sendto(pkt, ("255.255.255.255", 67))
        try:
            while True:
                data, _ = s.recvfrom(2048)
                if len(data) > 240 and struct.unpack("!I", data[4:8])[0] == xid:
                    print(socket.inet_ntoa(data[16:20]))
                    return
        except socket.timeout:
            continue
    sys.exit("DHCP yanıtı gelmedi")


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    try:
        {"listen": lambda: listen(args[0], args[1:]),
         "probe": lambda: probe(*args),
         "dhcp": lambda: dhcp(*args)}[cmd]()
    except (OSError, socket.timeout) as e:
        sys.exit(f"{cmd}: {e}")
