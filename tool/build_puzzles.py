#!/usr/bin/env python3
"""Builds assets/puzzles/puzzles.tsv.gz from the Lichess puzzle database (CC0).

Usage:
  curl -O https://database.lichess.org/lichess_db_puzzle.csv.zst
  zstd -dc lichess_db_puzzle.csv.zst | python3 tool/build_puzzles.py > assets/puzzles/puzzles.tsv.gz

Keeps well-tested, popular puzzles, balanced across 100-point rating bands from 400 to 2400,
and favours the themes the app teaches. Output lines: id, fen, moves, rating, themes (tab separated).
"""
import csv
import gzip
import random
import sys

PER_BAND = 1500
MIN_RATING, MAX_RATING = 400, 2400
TEACHING_THEMES = {
    'mateIn1', 'mateIn2', 'mateIn3', 'fork', 'pin', 'skewer', 'hangingPiece', 'discoveredAttack',
    'backRankMate', 'trappedPiece', 'sacrifice', 'deflection', 'attraction', 'promotion', 'defensiveMove',
}


def main():
    bands = {}
    reader = csv.reader(sys.stdin)
    next(reader)  # header
    for row in reader:
        pid, fen, moves, rating, rd, popularity, plays, themes = row[:8]
        rating, rd, popularity, plays = int(rating), int(rd), int(popularity), int(plays)
        if not (MIN_RATING <= rating < MAX_RATING) or rd > 90 or popularity < 85 or plays < 300:
            continue
        theme_set = set(themes.split())
        # Long puzzles (4+ player moves) are hard to follow for beginners.
        if len(moves.split()) > 8:
            continue
        band = rating // 100
        weight = 2 if theme_set & TEACHING_THEMES else 1
        bands.setdefault(band, []).append((weight, pid, fen, moves, rating, themes))

    rnd = random.Random(2026)
    picked = []
    for band, items in sorted(bands.items()):
        teaching = [i for i in items if i[0] == 2]
        other = [i for i in items if i[0] == 1]
        rnd.shuffle(teaching)
        rnd.shuffle(other)
        take = teaching[:int(PER_BAND * 0.8)]
        take += other[:PER_BAND - len(take)]
        if len(take) < PER_BAND:
            take += teaching[len(take):PER_BAND]
        picked.extend(take)
        print(f'band {band * 100}: {len(take)}', file=sys.stderr)

    picked.sort(key=lambda p: p[4])
    out = gzip.GzipFile(fileobj=sys.stdout.buffer, mode='wb', mtime=0, compresslevel=9)
    for _, pid, fen, moves, rating, themes in picked:
        out.write(f'{pid}\t{fen}\t{moves}\t{rating}\t{themes}\n'.encode())
    out.close()
    print(f'total {len(picked)}', file=sys.stderr)


if __name__ == '__main__':
    main()
