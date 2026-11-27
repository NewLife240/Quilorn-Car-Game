#!/usr/bin/env python3
"""Economy balance simulator for Rusty Roads.

Replays the first in-game days with a few scripted player strategies and prints the money curve.
It mirrors scripts/gameplay/economy.gd (job board, prices, production, hired routes, upkeep) and
reads goods / industries / vehicles straight from scripts/autoload/db.gd, so DB tuning is picked up
automatically. Travel times come from the real road network in assets/world/world.json.

Rule we balance for: a sensible player stays in the black and grows steadily; money only goes
into the red after bad investments or real mistakes.

    python3 tools/economy_sim.py              # all strategies, 8 days, 20 seeds
    python3 tools/economy_sim.py --days 12 --seeds 50 --legacy   # old rules (before the balance pass)

Time: 1 real second = 1 game minute, so one game day = 24 real minutes.
"""
import argparse
import heapq
import json
import math
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ------------------------------------------------------------------ data from db.gd
def _gd_dict(src: str, name: str) -> dict:
    i = src.index("var %s := {" % name)
    i = src.index("{", i)
    depth, j = 0, i
    while True:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = src[i:j + 1]
    body = re.sub(r"#[^\n]*", "", body)
    body = body.replace("true", "True").replace("false", "False")
    return eval(body, {"P": ""})


DB_SRC = open(os.path.join(ROOT, "scripts/autoload/db.gd")).read()
GOODS = _gd_dict(DB_SRC, "GOODS")
INDUSTRIES = _gd_dict(DB_SRC, "INDUSTRIES")
CONSUMERS = _gd_dict(DB_SRC, "CONSUMERS")
VEHICLES = _gd_dict(DB_SRC, "VEHICLES")
PARTS = _gd_dict(DB_SRC, "PARTS")

ECO_SRC = open(os.path.join(ROOT, "scripts/gameplay/economy.gd")).read()


def _gd_const(name: str, default: float) -> float:
    m = re.search(r"const %s := ([0-9.]+)" % name, ECO_SRC)
    return float(m.group(1)) if m else default


STORAGE = int(_gd_const("STORAGE", 80))
DRIVER_WAGE = int(_gd_const("DRIVER_WAGE", 260))
DRIVER_HIRE = int(_gd_const("DRIVER_HIRE", 500))
PRICE_FLOOR = _gd_const("PRICE_FLOOR", 0.55)
ROUTE_UNITS = int(_gd_const("ROUTE_UNITS", 8))
ROUTE_LEGS = _gd_const("ROUTE_LEGS", 1.0)
INDUSTRY_PRICE_CAP = _gd_const("INDUSTRY_PRICE_CAP", 1.45)
CONSUMER_STOCK_MAX = int(_gd_const("CONSUMER_STOCK_MAX", 10**9))
MAX_ACTIVE_JOBS = 3
SMALL_PARCEL_JOBS = int(_gd_const("SMALL_PARCEL_JOBS", 4))


# ------------------------------------------------------------------ world & roads
WORLD = json.load(open(os.path.join(ROOT, "assets/world/world.json")))
SITE_POS = {}
for o in WORLD["objects"]:
    if "industry" in o:
        SITE_POS[o["industry"]] = (o["x"], o["z"])
    elif o["kind"] in CONSUMERS:
        SITE_POS[o["kind"]] = (o["x"], o["z"])
    elif o["kind"] == "garage":
        SITE_POS["home"] = (o["x"], o["z"])
    elif o["kind"] == "car_market":
        SITE_POS["car_market"] = (o["x"], o["z"])
SITE_POS["junkyard"] = (WORLD["locations"]["junkyard"]["x"], WORLD["locations"]["junkyard"]["z"])

SPEED = {"asphalt": 19.0, "gravel": 12.5, "dirt": 7.5}  # m/s an average driver holds (corners, villages, mud)
nodes, adj = [], {}


def _add_edge(a, b, t):
    adj.setdefault(a, []).append((b, t))
    adj.setdefault(b, []).append((a, t))


for rd in WORLD["roads"]:
    base = len(nodes)
    sp = SPEED.get(rd["kind"], 12.0)
    for k, p in enumerate(rd["pts"]):
        nodes.append((p[0], p[2]))
        if k > 0:
            a, b = nodes[-2], nodes[-1]
            _add_edge(base + k - 1, base + k, math.dist(a, b) / sp)
# junctions: connect road points that touch another road
for i in range(len(nodes)):
    for j in range(i + 1, len(nodes)):
        if abs(nodes[i][0] - nodes[j][0]) < 9 and abs(nodes[i][1] - nodes[j][1]) < 9 and math.dist(nodes[i], nodes[j]) < 9:
            _add_edge(i, j, math.dist(nodes[i], nodes[j]) / 8.0)


def _nearest_node(p):
    return min(range(len(nodes)), key=lambda i: math.dist(nodes[i], p))


def _dijkstra(src):
    dist = {src: 0.0}
    pq = [(0.0, src)]
    while pq:
        d, u = heapq.heappop(pq)
        if d > dist.get(u, 1e18):
            continue
        for v, w in adj.get(u, []):
            nd = d + w
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                heapq.heappush(pq, (nd, v))
    return dist


_SITE_NODE = {k: _nearest_node(p) for k, p in SITE_POS.items()}
_D = {k: _dijkstra(n) for k, n in _SITE_NODE.items()}


def travel_s(a: str, b: str) -> float:
    """Seconds (= game minutes) to drive from site a to site b."""
    if a == b:
        return 0.0
    na, nb = _SITE_NODE[a], _SITE_NODE[b]
    off = (math.dist(SITE_POS[a], nodes[na]) + math.dist(SITE_POS[b], nodes[nb])) / 5.0
    return _D[a].get(nb, math.dist(SITE_POS[a], SITE_POS[b]) / 6.0) + off


def straight(a: str, b: str) -> float:
    return math.dist(SITE_POS[a], SITE_POS[b])


# ------------------------------------------------------------------ economy (mirror of economy.gd)
class Eco:
    def __init__(self, rng: random.Random, legacy: bool):
        self.rng = rng
        self.legacy = legacy
        self.money = 1800
        self.minute = 7.5 * 60  # absolute game minutes since day 1 00:00 minus a day
        self.day = 1
        self.industries = {}
        for k, d in INDUSTRIES.items():
            self.industries[k] = {"owner": "npc", "level": 1, "prod": 0.0,
                                  "inp": {g: rng.randint(4, 16) for g in d["in"]},
                                  "out": {g: rng.randint(6, 20) for g in d["out"]}}
        self.consumers = {k: {g: rng.randint(5, 25) for g in d["buys"]} for k, d in CONSUMERS.items()}
        self.jobs, self.routes = [], []
        self.next_id = 1
        self.last_hour = int(self.minute // 60)
        self.last_cost_day = self.day
        self.log = []          # (day, money)
        self.ledger = {}       # reason -> total
        self.min_money = self.money
        self._gen_jobs()

    # money
    def add(self, amount, reason):
        self.money += amount
        self.ledger[reason] = self.ledger.get(reason, 0) + amount
        self.min_money = min(self.min_money, self.money)

    def spend(self, amount, reason):
        if self.money < amount:
            return False
        self.add(-amount, reason)
        return True

    # prices
    def price(self, good, site):
        base = GOODS[good]["price"]
        stock = 20.0
        cap = 1.45
        if site in self.consumers:
            stock = float(self.consumers[site].get(good, 20))
        elif site in self.industries:
            stock = float(self.industries[site]["inp"].get(good, 20))
            if not self.legacy:
                cap = INDUSTRY_PRICE_CAP
        floor = 0.55 if self.legacy else PRICE_FLOOR
        return int(base * min(cap, max(floor, 1.45 - stock / 50.0)))

    def buyers_of(self, good):
        out = [k for k, d in CONSUMERS.items() if good in d["buys"]]
        out += [k for k, d in INDUSTRIES.items() if good in d["in"]]
        return out

    def receive(self, site, good, units):
        if site in self.consumers:
            cap = 10**9 if self.legacy else CONSUMER_STOCK_MAX
            self.consumers[site][good] = min(cap, self.consumers[site].get(good, 0) + units)
        elif site in self.industries and good in INDUSTRIES[site]["in"]:
            ind = self.industries[site]
            ind["inp"][good] = min(STORAGE * ind["level"] * 2, ind["inp"].get(good, 0) + units)

    # jobs
    def _gen_jobs(self):
        tries = 0
        while len(self.jobs) < 14 and tries < 40:
            tries += 1
            if self.rng.random() < 0.35:
                keys = list(self.industries) + list(self.consumers)
                a, b = self.rng.choice(keys), self.rng.choice(keys)
                if a == b:
                    continue
                units = self.rng.randint(1, 2) if self.rng.random() < 0.7 else self.rng.randint(3, 6)
                self._add_job("parcel", units, a, b, int(units * (45 + straight(a, b) * 0.16)))
            else:
                srcs = [k for k in self.industries if INDUSTRIES[k]["out"]]
                a = self.rng.choice(srcs)
                g = self.rng.choice(list(self.industries[a]["out"]))
                if self.industries[a]["out"][g] < 4:
                    continue
                dsts = self.buyers_of(g)
                b = self.rng.choice(dsts)
                units = self.rng.randint(2, 12)
                if GOODS[g]["kind"] == "crate":
                    units = self.rng.randint(2, 8)
                self._add_job(g, units, a, b, int(units * (28 + straight(a, b) * 0.17)))
        if self.legacy:
            return
        # keep a few small parcel runs on the board so the starter car always has work
        small = sum(1 for j in self.jobs if j["good"] == "parcel" and j["units"] <= 2)
        keys = list(self.industries) + list(self.consumers)
        tries = 0
        while small < SMALL_PARCEL_JOBS and tries < 20:
            tries += 1
            a, b = self.rng.choice(keys), self.rng.choice(keys)
            if a == b:
                continue
            units = self.rng.randint(1, 2)
            self._add_job("parcel", units, a, b, int(units * (45 + straight(a, b) * 0.16)))
            small += 1

    def _add_job(self, good, units, a, b, pay):
        self.jobs.append({"id": self.next_id, "good": good, "units": units, "from": a, "to": b, "pay": pay,
                          "expires": self.minute + self.rng.randint(240, 720)})
        self.next_id += 1

    # simulation
    def _tick_minute(self):
        for k, ind in self.industries.items():
            d = INDUSTRIES[k]
            rate = d["rate"] * (1.0 + 0.5 * (ind["level"] - 1)) / 60.0
            full = any(ind["out"].get(g, 0) >= STORAGE * ind["level"] for g in d["out"])
            have = all(ind["inp"].get(g, 0) >= n for g, n in d["in"].items())
            if not full and have:
                ind["prod"] += rate
                while ind["prod"] >= 1.0:
                    ind["prod"] -= 1.0
                    for g, n in d["in"].items():
                        ind["inp"][g] -= n
                    for g, n in d["out"].items():
                        ind["out"][g] = ind["out"].get(g, 0) + n
        for k, st in self.consumers.items():
            for g in st:
                if self.rng.random() < CONSUMERS[k]["use_rate"] / 60.0:
                    st[g] = max(0, st[g] - 1)
        for r in self.routes:
            r["t"] += 1.0
            if r["t"] >= r["trip"]:
                r["t"] = 0.0
                self._route_trip(r)

    def _route_trip(self, r):
        src = self.industries.get(r["from"])
        if not src or src["owner"] != "player":
            return
        units = min(ROUTE_UNITS * r["trucks"], src["out"].get(r["good"], 0))
        if units <= 0:
            return
        src["out"][r["good"]] -= units
        if r["to"] in self.industries and self.industries[r["to"]]["owner"] == "player":
            self.receive(r["to"], r["good"], units)
        else:
            p = self.price(r["good"], r["to"])
            self.receive(r["to"], r["good"], units)
            self.add(p * units, "route sales")

    def _on_hour(self, day, hour):
        for k, ind in self.industries.items():
            d = INDUSTRIES[k]
            if ind["owner"] == "npc":
                for g in d["in"]:
                    if self.rng.random() < 0.35:
                        ind["inp"][g] = min(STORAGE, ind["inp"][g] + self.rng.randint(1, 3))
                for g in d["out"]:
                    if ind["out"][g] > 40 and self.rng.random() < 0.5:
                        ind["out"][g] -= self.rng.randint(2, 6)
        self._gen_jobs()
        self.jobs = [j for j in self.jobs if j["expires"] > self.minute]
        if self.legacy:
            if hour == 0:
                self._daily_costs()
        elif day != self.last_cost_day:
            self.last_cost_day = day
            self._daily_costs()

    def _daily_costs(self):
        total = sum(INDUSTRIES[k]["upkeep"] * ind["level"] for k, ind in self.industries.items() if ind["owner"] == "player")
        total += (260 if self.legacy else DRIVER_WAGE) * sum(r["trucks"] for r in self.routes)
        if total:
            self.add(-total, "upkeep & wages")

    def advance(self, minutes):
        """Run the world for `minutes` game minutes (the player is busy driving)."""
        for _ in range(int(round(minutes))):
            self.minute += 1
            self._tick_minute()
            self.day = int(self.minute // 1440) + 1
            hr = int(self.minute // 60)
            if hr != self.last_hour:
                self.last_hour = hr
                self._on_hour(self.day, hr % 24)

    def sleep(self):
        """Bed after 19:00 -> 07:00 next morning."""
        h = (self.minute % 1440) / 60.0
        target = (self.minute // 1440 + (1 if h >= 19 else 0)) * 1440 + 7 * 60
        if self.legacy:
            # old behaviour: the clock jumps, nothing in between happens (no midnight -> no upkeep)
            self.minute = target
            self.day = int(self.minute // 1440) + 1
            hr = int(self.minute // 60)
            self.last_hour = hr
            self._on_hour(self.day, hr % 24)
        else:
            self.advance(target - self.minute)

    # business actions
    def buy_industry(self, k):
        if self.spend(INDUSTRIES[k]["price"], "bought business"):
            self.industries[k]["owner"] = "player"
            return True
        return False

    def upgrade(self, k):
        ind = self.industries[k]
        if self.legacy:
            cost = int(INDUSTRIES[k]["price"] * 0.6 * ind["level"])
        else:
            cost = int(INDUSTRIES[k]["price"] * 0.6 * ind["level"])
        if ind["level"] < 3 and self.spend(cost, "upgrades"):
            ind["level"] += 1

    def hire(self, a, b, g):
        if not self.spend(DRIVER_HIRE, "driver hiring"):
            return False
        for r in self.routes:
            if (r["from"], r["to"], r["good"]) == (a, b, g):
                r["trucks"] += 1
                return True
        legs = 1.0 if self.legacy else ROUTE_LEGS  # legacy: drivers teleported back empty
        self.routes.append({"from": a, "to": b, "good": g, "trucks": 1, "t": 0.0, "trip": 30.0 + legs * straight(a, b) / 6.0})
        return True


# ------------------------------------------------------------------ player strategies
STOP_S = 40.0      # park in a marker, press J, check the tablet
CHOOSE_S = 15.0    # pick the next job


class Player:
    """Greedy delivery driver: takes the best-paying job (per minute) the current vehicle can carry."""

    pay_mult = 1.0       # cargo condition / lateness
    cancel_rate = 0.0
    wander = 1.0         # real-time inefficiency factor on driving
    day_end_hour = 21.0

    def __init__(self, eco: Eco, rng: random.Random):
        self.eco, self.rng = eco, rng
        self.pos = "home"
        self.vehicle = "kombi"
        self.notes = []

    def cap(self):
        return VEHICLES[self.vehicle]["cargo"]

    def kinds(self):
        return VEHICLES[self.vehicle]["kinds"]

    def speed_mult(self):
        return 0.85 if VEHICLES[self.vehicle]["cls"] == "big" else 1.0

    def drive(self, a, b):
        t = travel_s(a, b) * self.wander / self.speed_mult()
        self.eco.advance(t)
        self.pos = b

    def best_job(self):
        best, bs = None, 0.0
        for j in self.eco.jobs:
            if GOODS[j["good"]]["kind"] not in self.kinds() or j["units"] > self.cap():
                continue
            t = (travel_s(self.pos, j["from"]) + travel_s(j["from"], j["to"])) * self.wander / self.speed_mult() + 2 * STOP_S + CHOOSE_S
            s = j["pay"] / t
            if s > bs:
                best, bs = j, s
        return best

    def work_one(self):
        j = self.best_job()
        self.eco.advance(CHOOSE_S)
        if j is None:
            self.eco.advance(60)
            return
        if j in self.eco.jobs:
            self.eco.jobs.remove(j)
        self.drive(self.pos, j["from"])
        self.eco.advance(STOP_S)
        if self.rng.random() < self.cancel_rate:
            self.eco.add(-int(j["pay"] * 0.1), "job cancelled")
            return
        if j["from"] in self.eco.industries and j["good"] != "parcel":
            ind = self.eco.industries[j["from"]]
            ind["out"][j["good"]] = max(0, ind["out"].get(j["good"], 0) - j["units"])
        self.drive(j["from"], j["to"])
        self.eco.advance(STOP_S)
        pay = j["pay"] * self.pay_mult
        if self.eco.minute > j["expires"] + 240:
            pay *= 0.7
        self.eco.add(int(pay), "deliveries")
        self.eco.receive(j["to"], j["good"], j["units"])

    def running_costs(self, minutes):
        # fuel + wear: ~0.0047 L/s at half throttle; wear is cents per minute (see vehicle.gd)
        fuel_l = minutes * 0.0047 * (2.4 if VEHICLES[self.vehicle]["cls"] == "big" else 1.0)
        self.eco.add(-int(round(fuel_l * fuel_price(self.eco.legacy))), "fuel")
        self.eco.add(-int(round(minutes / 3600.0 * 50)), "maintenance")

    def decide(self):
        """Spend money: overridden per strategy."""

    def play_day(self):
        start_min = self.eco.minute
        while (self.eco.minute % 1440) / 60.0 < self.day_end_hour and (self.eco.minute % 1440) / 60.0 >= 6.9:
            self.decide()
            self.work_one()
        self.running_costs(self.eco.minute - start_min)
        self.eco.sleep()


def fuel_price(legacy):
    return 2.2 if legacy else _gd_const("FUEL_PRICE", 2.2)


def used_car_cost(vid, rng, legacy):
    """Typical car-market price for a worn car + junkyard parts to make it drivable."""
    d = VEHICLES[vid]
    parts = sum(p["price"] for k, p in PARTS.items() if k in ("gearbox", "radiator", "battery", "ignition_coil", "fuel_tank",
                                                           "exhaust", "carburetor", "air_filter", "spark_plugs", "alternator", "starter"))
    parts += PARTS[d["engine"]]["price"] + 4 * PARTS[d["wheel"]]["price"]
    cond = 0.5
    value = d["price"] * 0.35 + parts * (0.25 + 0.6 * cond)
    return int(value * rng.uniform(0.85, 1.2)) + 250  # + a few junkyard parts / repair kits


class Sensible(Player):
    """Delivers carefully, upgrades the van when it has a buffer, buys one cheap business it can supply
    and hires as many drivers as the output supports."""
    name = "sensible"

    def decide(self):
        e = self.eco
        if self.vehicle == "kombi":
            c = used_car_cost("bukhanka", self.rng, e.legacy)
            if e.money > c + 1500:
                e.add(-c, "bought vehicle")
                self.vehicle = "bukhanka"
                self.notes.append("day %d: used Bukhanka" % e.day)
            return
        if not any(i["owner"] == "player" for i in e.industries.values()):
            if e.money > INDUSTRIES["sunflower_farm"]["price"] + 2 * DRIVER_HIRE + 1500:
                e.buy_industry("sunflower_farm")
                e.hire("sunflower_farm", "warehouse", "sunflower")
                e.hire("sunflower_farm", "warehouse", "sunflower")
                self.notes.append("day %d: sunflower farm + 2 drivers" % e.day)
            return
        if self.vehicle == "bukhanka" and e.money > 9800 + 3000:
            e.add(-int(9800 * 0.75), "bought vehicle")
            self.vehicle = "stepvan"
            self.notes.append("day %d: step van" % e.day)


class Careless(Player):
    """Same plan as sensible, but crashes into things (damaged cargo), delivers late, cancels jobs."""
    name = "careless"
    pay_mult = 0.65
    cancel_rate = 0.15
    wander = 1.35

    decide = Sensible.decide

    def play_day(self):
        # a crash every day or so: radiator + a repair kit or two
        if self.rng.random() < 0.6:
            self.eco.add(-(170 if self.rng.random() < 0.3 else 60), "crash repairs")
        super().play_day()


class BadInvestor(Player):
    """Delivers fine, then buys the biggest factory it can afford without any input supply and
    hires drivers on routes from it; upgrades on top."""
    name = "bad investor"

    def decide(self):
        e = self.eco
        if self.vehicle == "kombi":
            c = used_car_cost("bukhanka", self.rng, e.legacy)
            if e.money > c + 1500:
                e.add(-c, "bought vehicle")
                self.vehicle = "bukhanka"
            return
        if not e.industries["sawmill"]["owner"] == "player":
            if e.money >= INDUSTRIES["sawmill"]["price"] + 3 * DRIVER_HIRE:
                e.buy_industry("sawmill")  # needs logs, nobody brings them
                for _ in range(3):
                    e.hire("sawmill", "warehouse", "planks")
                self.notes.append("day %d: sawmill (no log supply) + 3 drivers" % e.day)
            return
        if e.industries["sawmill"]["level"] < 2 and e.money > 14000:
            e.upgrade("sawmill")
            self.notes.append("day %d: upgraded sawmill" % e.day)


class Rusher(Player):
    """Min-maxer: plays through the night, buys the biggest earner as soon as possible."""
    name = "min-maxer"
    day_end_hour = 23.9

    def decide(self):
        e = self.eco
        if self.vehicle == "kombi":
            c = used_car_cost("bukhanka", self.rng, e.legacy)
            if e.money > c:
                e.add(-c, "bought vehicle")
                self.vehicle = "bukhanka"
            return
        owned = [k for k, i in e.industries.items() if i["owner"] == "player"]
        for k in ("lumber_camp", "sunflower_farm", "grain_farm", "quarry"):
            if k not in owned and e.money >= INDUSTRIES[k]["price"] + 2 * DRIVER_HIRE:
                e.buy_industry(k)
                dst = "warehouse"
                e.hire(k, dst, list(INDUSTRIES[k]["out"])[0])
                e.hire(k, dst, list(INDUSTRIES[k]["out"])[0])
                self.notes.append("day %d: %s" % (e.day, k))
                return
        if self.vehicle != "truck" and e.money > 24000 * 0.7 + 2000:
            e.add(-int(24000 * 0.7), "bought vehicle")
            self.vehicle = "truck"
            self.notes.append("day %d: timber truck" % e.day)


class Idle(Player):
    """Owns a business but stops working (tests that passive income alone isn't a money printer)."""
    name = "idle owner"


STRATS = [Sensible, Careless, BadInvestor, Rusher]


def run(strat, seed, days, legacy):
    rng = random.Random(seed)
    eco = Eco(rng, legacy)
    p = strat(eco, rng)
    curve = []
    for _ in range(days):
        p.play_day()
        curve.append(eco.money)
    return curve, eco, p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=8)
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--legacy", action="store_true", help="simulate the rules before the balance pass")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    print("rules: %s   days: %d   seeds: %d   (1 game day = 24 real minutes)" % ("legacy" if a.legacy else "current", a.days, a.seeds))
    for s in STRATS:
        curves, mins, ledgers, notes = [], [], [], []
        for seed in range(a.seeds):
            c, eco, p = run(s, seed, a.days, a.legacy)
            curves.append(c)
            mins.append(eco.min_money)
            ledgers.append(eco.ledger)
            notes.append(p.notes)
        med = [sorted(col)[len(col) // 2] for col in zip(*curves)]
        low = [sorted(col)[len(col) // 10] for col in zip(*curves)]
        print("\n%-13s median money at end of day: %s" % (s.name, "  ".join("%6d" % m for m in med)))
        print("%-13s 10th percentile:            %s" % ("", "  ".join("%6d" % m for m in low)))
        print("%-13s lowest balance seen (median): %d   runs that went below 0: %d/%d" % (
            "", sorted(mins)[len(mins) // 2], sum(1 for m in mins if m < 0), len(mins)))
        keys = sorted({k for l in ledgers for k in l})
        print("%-13s avg ledger: %s" % ("", ", ".join("%s %+d" % (k, sum(l.get(k, 0) for l in ledgers) / len(ledgers)) for k in keys)))
        if a.verbose:
            print("%-13s seed 0: %s" % ("", "; ".join(notes[0])))


if __name__ == "__main__":
    main()
