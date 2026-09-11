#!/usr/bin/env python3
"""
Continuous GNOME Shell Screencast Recorder and MP4 Converter.
Maintains an active DBus connection during recording to prevent GNOME Shell
from terminating the screencast prematurely ("Sender has vanished").
"""

import argparse
import json
import os
import shutil
import signal
import sys
import time

try:
    import dbus
    from gi.repository import GLib
except ImportError as e:
    sys.exit(f"Missing DBus/GLib dependencies: {e}")

try:
    import cv2
except ImportError:
    cv2 = None


def run_recorder(info_file: str):
    bus = dbus.SessionBus()
    try:
        obj = bus.get_object('org.gnome.Shell.Screencast', '/org/gnome/Shell/Screencast')
        iface = dbus.Interface(obj, 'org.gnome.Shell.Screencast')
    except Exception as e:
        sys.exit(f"Impossible de se connecter à org.gnome.Shell.Screencast: {e}")

    loop = GLib.MainLoop()
    start_time = time.time()

    # Note: GNOME 46 deprecates passing '.webm' in file_template
    success, filename = iface.Screencast('hc10_pick_place_%d_%t', {})
    if not success:
        sys.exit("Échec du démarrage du screencast GNOME")

    info = {
        'pid': os.getpid(),
        'file': filename,
        'start_time': start_time,
        'status': 'recording',
    }
    with open(info_file, 'w') as f:
        json.dump(info, f)

    print(f"Enregistrement vidéo démarré: {filename} (PID: {os.getpid()})", flush=True)

    def on_stop_signal():
        print("Arrêt de l'enregistrement demandé...", flush=True)
        stop_time = time.time()
        try:
            iface.StopScreencast()
        except Exception as err:
            print(f"Erreur StopScreencast: {err}", file=sys.stderr)

        def finalize():
            info['stop_time'] = stop_time
            info['duration'] = max(stop_time - start_time, 0.1)
            info['status'] = 'stopped'
            with open(info_file, 'w') as f:
                json.dump(info, f)
            loop.quit()
            return GLib.SOURCE_REMOVE

        # Laisser 2 secondes à PipeWire / GStreamer pour clore le conteneur WebM
        GLib.timeout_add_seconds(2, finalize)
        return GLib.SOURCE_REMOVE

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, on_stop_signal)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, on_stop_signal)

    try:
        loop.run()
    except Exception as e:
        print(f"Exception dans la boucle screencast: {e}", file=sys.stderr)

    print(f"Enregistrement vidéo terminé ({info.get('duration', 0):.1f}s)", flush=True)


def stop_recorder(info_file: str):
    if not os.path.exists(info_file):
        print(f"Fichier d'information {info_file} introuvable", file=sys.stderr)
        return False

    with open(info_file, 'r') as f:
        info = json.load(f)

    pid = info.get('pid')
    if not pid:
        return False

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return True

    # Attendre la fin du processus
    for _ in range(30):
        time.sleep(0.2)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
    return True


def convert_video(info_file: str, target_webm: str, target_mp4: str):
    if not os.path.exists(info_file):
        sys.exit(f"Fichier d'information {info_file} introuvable")

    with open(info_file, 'r') as f:
        info = json.load(f)

    src_webm = info.get('file')
    if not src_webm or not os.path.exists(src_webm):
        sys.exit(f"Fichier vidéo source {src_webm} inexistant")

    duration = info.get('duration', 10.0)

    # Copie WebM
    if target_webm:
        shutil.copyfile(src_webm, target_webm)
        webm_mb = os.path.getsize(target_webm) / (1024 * 1024)
        print(f"Vidéo WebM enregistrée: {target_webm} ({webm_mb:.2f} Mo)")

    # Conversion MP4
    if target_mp4 and cv2 is not None:
        cap = cv2.VideoCapture(src_webm)
        if not cap.isOpened():
            sys.exit(f"Impossible d'ouvrir {src_webm} avec OpenCV")

        frames = []
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            frames.append(frame)
        cap.release()

        if not frames:
            sys.exit(f"Aucune image trouvée dans {src_webm}")

        fps = len(frames) / duration
        fps = max(5.0, min(60.0, fps))

        h, w, _ = frames[0].shape
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(target_mp4, fourcc, fps, (w, h))
        for f in frames:
            out.write(f)
        out.release()

        mp4_mb = os.path.getsize(target_mp4) / (1024 * 1024)
        print(f"Vidéo MP4 prête: {target_mp4} ({mp4_mb:.2f} Mo, {w}x{h}, {len(frames)} images à {fps:.1f} fps)")


def main():
    parser = argparse.ArgumentParser(description="GNOME Screencast Utility")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_p = subparsers.add_parser("run")
    run_p.add_argument("--info-file", required=True)

    stop_p = subparsers.add_parser("stop")
    stop_p.add_argument("--info-file", required=True)

    conv_p = subparsers.add_parser("convert")
    conv_p.add_argument("--info-file", required=True)
    conv_p.add_argument("--target-webm", required=False, default="")
    conv_p.add_argument("--target-mp4", required=False, default="")

    args = parser.parse_args()

    if args.command == "run":
        run_recorder(args.info_file)
    elif args.command == "stop":
        stop_recorder(args.info_file)
    elif args.command == "convert":
        convert_video(args.info_file, args.target_webm, args.target_mp4)


if __name__ == '__main__':
    main()
