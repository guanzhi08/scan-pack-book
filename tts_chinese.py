"""
Convert a Traditional Chinese text file to an MP3 audio file
with Taiwan Mandarin accent.

Default engine: edge-tts (Microsoft Edge TTS, Taiwan Mandarin voices)
Optional engine: coqui (Coqui TTS XTTS v2 with voice cloning)

Usage:
    python tts_chinese.py input.txt
    python tts_chinese.py input.txt -o output.mp3
    python tts_chinese.py input.txt --voice zh-TW-YunJheNeural
    python tts_chinese.py input.txt --engine coqui --speaker-wav reference.wav
"""

import argparse
import os
import re
import sys
import tempfile


# --------------- Text chunking ---------------

# Chinese + English punctuation marks suitable for splitting
_SPLIT_PATTERN = re.compile(
    r"(?<=[。！？；\.!?;\n])"  # split after Chinese or English sentence-ending punctuation
)

def split_text(text, max_chars=200):
    """
    Split Chinese text into chunks of at most *max_chars* characters,
    preferring to break at sentence-ending punctuation.
    """
    # First, split at sentence boundaries
    segments = _SPLIT_PATTERN.split(text)
    segments = [s.strip() for s in segments if s.strip()]

    chunks = []
    current = ""
    for seg in segments:
        if len(current) + len(seg) <= max_chars:
            current += seg
        else:
            if current:
                chunks.append(current)
            # If a single segment is longer than max_chars, split it further
            while len(seg) > max_chars:
                # Try to split at comma or other minor punctuation
                cut = _find_minor_break(seg, max_chars)
                chunks.append(seg[:cut])
                seg = seg[cut:].strip()
            current = seg
    if current:
        chunks.append(current)
    return chunks


_MINOR_BREAK = re.compile(r"[，、：「」『』（）\-–—,;:()\[\]]")  # Chinese + English minor breaks

def _find_minor_break(text, max_chars):
    """Find the best break point within *max_chars* of *text*."""
    best = max_chars
    for m in _MINOR_BREAK.finditer(text):
        pos = m.end()
        if pos <= max_chars:
            best = pos
    return best


# --------------- Audio helpers ---------------

def concat_wav_files(wav_paths, output_path):
    """Concatenate multiple WAV files into one using the wave module."""
    import wave

    if not wav_paths:
        return

    with wave.open(wav_paths[0], "rb") as first:
        params = first.getparams()

    with wave.open(output_path, "wb") as out:
        out.setparams(params)
        for path in wav_paths:
            with wave.open(path, "rb") as w:
                out.writeframes(w.readframes(w.getnframes()))


def wav_to_mp3(wav_path, mp3_path):
    """Convert WAV to MP3. Tries pydub (ffmpeg) first, falls back to lameenc."""
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_wav(wav_path)
        audio.export(mp3_path, format="mp3", bitrate="192k")
        return
    except Exception:
        pass

    try:
        import lameenc
        import wave

        with wave.open(wav_path, "rb") as w:
            pcm = w.readframes(w.getnframes())
            rate = w.getframerate()
            channels = w.getnchannels()
            width = w.getsampwidth()

        encoder = lameenc.Encoder()
        encoder.set_bit_rate(192)
        encoder.set_in_sample_rate(rate)
        encoder.set_channels(channels)
        encoder.set_quality(2)
        mp3_data = encoder.encode(pcm) + encoder.flush()

        with open(mp3_path, "wb") as f:
            f.write(mp3_data)
        return
    except Exception:
        pass

    # Last resort: just keep the wav and rename
    print("Warning: Neither pydub (ffmpeg) nor lameenc is available.")
    print("         Saving output as WAV instead of MP3.")
    import shutil
    out_wav = os.path.splitext(mp3_path)[0] + ".wav"
    shutil.copy2(wav_path, out_wav)
    print(f"  -> {out_wav}")
    sys.exit(0)


# --------------- Edge-TTS engine ---------------

def run_edge_tts(text, output_path, voice, rate, max_chars):
    """Synthesize text to MP3 using edge-tts (Microsoft Edge TTS)."""
    import asyncio

    try:
        import edge_tts
    except ImportError:
        print("Error: edge-tts is not installed.")
        print("  Install it with:  pip install edge-tts")
        sys.exit(1)

    chunks = split_text(text, max_chars)
    print(f"Text split into {len(chunks)} chunk(s).")
    print(f"Voice: {voice}")

    tmp_dir = tempfile.mkdtemp(prefix="tts_tw_")
    mp3_parts = []

    async def synthesize_chunk(i, chunk):
        part_path = os.path.join(tmp_dir, f"part_{i:04d}.mp3")
        print(f"  Synthesizing chunk {i + 1}/{len(chunks)}  "
              f"({len(chunk)} chars) ...")
        communicate = edge_tts.Communicate(chunk, voice, rate=rate)
        await communicate.save(part_path)
        return part_path

    async def synthesize_all():
        for i, chunk in enumerate(chunks):
            path = await synthesize_chunk(i, chunk)
            mp3_parts.append(path)

    asyncio.run(synthesize_all())

    # Concatenate MP3 parts
    if len(mp3_parts) == 1:
        import shutil
        shutil.move(mp3_parts[0], output_path)
    else:
        print("Concatenating audio chunks ...")
        with open(output_path, "wb") as out_f:
            for part in mp3_parts:
                with open(part, "rb") as in_f:
                    out_f.write(in_f.read())

    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)
    print(f"Done!  Output saved to: {output_path}")


# --------------- Coqui TTS engine ---------------

def _patch_torch_load():
    """PyTorch 2.6+ changed torch.load default to weights_only=True.
    Coqui TTS needs weights_only=False."""
    import torch
    _original = torch.load
    def _patched(*args, **kwargs):
        if "weights_only" not in kwargs:
            kwargs["weights_only"] = False
        return _original(*args, **kwargs)
    torch.load = _patched


def run_coqui_tts(text, output_path, speaker_wav, model, language, max_chars, gpu):
    """Synthesize text using Coqui TTS (XTTS v2 with voice cloning)."""
    _patch_torch_load()

    XTTS_MODEL = "tts_models/multilingual/multi-dataset/xtts_v2"
    model_name = model or XTTS_MODEL

    is_xtts = "xtts" in model_name.lower()
    if is_xtts and not speaker_wav:
        print("Error: XTTS v2 requires a reference speaker WAV for voice cloning.")
        print("       Provide one with --speaker-wav <path.wav>")
        sys.exit(1)

    if speaker_wav and not os.path.isfile(speaker_wav):
        print(f"Error: Speaker WAV file not found: {speaker_wav}")
        sys.exit(1)

    print(f"Loading TTS model: {model_name} ...")
    try:
        from TTS.api import TTS
    except ImportError:
        print("Error: Coqui TTS is not installed.")
        print("  Install it with:  pip install TTS")
        sys.exit(1)

    tts = TTS(model_name=model_name, gpu=gpu)

    chunks = split_text(text, max_chars)
    print(f"Text split into {len(chunks)} chunk(s).")

    tmp_dir = tempfile.mkdtemp(prefix="tts_cn_")
    wav_parts = []

    for i, chunk in enumerate(chunks):
        part_path = os.path.join(tmp_dir, f"part_{i:04d}.wav")
        print(f"  Synthesizing chunk {i + 1}/{len(chunks)}  "
              f"({len(chunk)} chars) ...")

        kwargs = {"text": chunk, "file_path": part_path}
        if is_xtts:
            kwargs["language"] = language
        if speaker_wav:
            kwargs["speaker_wav"] = speaker_wav

        tts.tts_to_file(**kwargs)
        wav_parts.append(part_path)

    if len(wav_parts) == 1:
        combined_wav = wav_parts[0]
    else:
        combined_wav = os.path.join(tmp_dir, "combined.wav")
        print("Concatenating audio chunks ...")
        concat_wav_files(wav_parts, combined_wav)

    print("Converting to MP3 ...")
    wav_to_mp3(combined_wav, output_path)

    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)
    print(f"Done!  Output saved to: {output_path}")


# --------------- Main ---------------

# Available Taiwan Mandarin voices (edge-tts)
#   zh-TW-HsiaoChenNeural  (female)
#   zh-TW-YunJheNeural     (male)
#   zh-TW-HsiaoYuNeural    (female)

def main():
    parser = argparse.ArgumentParser(
        description="Convert Traditional Chinese text to Taiwan Mandarin speech (MP3)"
    )
    parser.add_argument("input", help="Path to a .txt file or a folder of .txt files")
    parser.add_argument(
        "-o", "--output",
        help="Output MP3 path (file mode) or output folder (folder mode). "
             "Default: same name/location with .mp3 extension",
    )
    parser.add_argument(
        "--engine", choices=["edge", "coqui"], default="edge",
        help="TTS engine: 'edge' (default, Taiwan Mandarin) or 'coqui' (XTTS v2 cloning)",
    )
    parser.add_argument(
        "--voice", default="zh-TW-HsiaoChenNeural",
        help="Edge-TTS voice name (default: zh-TW-HsiaoChenNeural, female Taiwan Mandarin)",
    )
    parser.add_argument(
        "--rate", type=int, default=0,
        help="Speech rate percent adjustment, e.g. -10 or +10 (default: 0)",
    )
    parser.add_argument(
        "--speaker-wav",
        help="[coqui only] Reference WAV for voice cloning",
    )
    parser.add_argument(
        "--model", default=None,
        help="[coqui only] Coqui TTS model name (default: xtts_v2)",
    )
    parser.add_argument(
        "--language", default="zh-cn",
        help="[coqui only] Language code (default: zh-cn)",
    )
    parser.add_argument(
        "--max-chars", type=int, default=200,
        help="Max characters per synthesis chunk (default: 200)",
    )
    parser.add_argument(
        "--gpu", action="store_true",
        help="[coqui only] Use GPU for synthesis",
    )
    args = parser.parse_args()

    # --- Collect txt files ---
    if os.path.isdir(args.input):
        import glob
        txt_files = sorted(glob.glob(os.path.join(args.input, "*.txt")))
        if not txt_files:
            print(f"Error: No .txt files found in folder: {args.input}")
            sys.exit(1)
        out_dir = args.output or args.input
        if not os.path.isdir(out_dir):
            os.makedirs(out_dir, exist_ok=True)
        file_pairs = []
        for tf in txt_files:
            mp3_name = os.path.splitext(os.path.basename(tf))[0] + ".mp3"
            file_pairs.append((tf, os.path.join(out_dir, mp3_name)))
        print(f"Folder mode: found {len(file_pairs)} .txt file(s) in {args.input}")
    elif os.path.isfile(args.input):
        output_path = args.output or os.path.splitext(args.input)[0] + ".mp3"
        file_pairs = [(args.input, output_path)]
    else:
        print(f"Error: Input not found: {args.input}")
        sys.exit(1)

    # --- Process each file ---
    for idx, (txt_path, mp3_path) in enumerate(file_pairs):
        if len(file_pairs) > 1:
            print(f"\n=== [{idx + 1}/{len(file_pairs)}] {os.path.basename(txt_path)} ===")

        with open(txt_path, "r", encoding="utf-8") as f:
            text = f.read().strip()

        if not text:
            print(f"  Skipping empty file: {txt_path}")
            continue

        if args.engine == "edge":
            rate_str = f"{args.rate:+d}%"
            run_edge_tts(text, mp3_path, args.voice, rate_str, args.max_chars)
        else:
            run_coqui_tts(
                text, mp3_path, args.speaker_wav,
                args.model, args.language, args.max_chars, args.gpu,
            )

    if len(file_pairs) > 1:
        print(f"\nAll done! Processed {len(file_pairs)} file(s).")


if __name__ == "__main__":
    main()
