// Regenerates Vigil's interface sounds into Resources/Sounds.
//
//   swift scripts/make-sounds.swift [output-dir]
//
// Synthesised rather than recorded, for the same reason the wordmark is
// outlined: the sounds are then a function of this file and can be adjusted by
// changing a number, and nothing in the repository is a binary nobody can
// reproduce. They are built from a handful of sine partials under an
// exponential decay, which is the shape of something small being struck.
//
// The rules they follow, in case they are ever retuned:
//   - One note. A two-note figure is a phrase, and a phrase is a ringtone: it
//     announces itself and asks to be listened to. The first version of these
//     was three little arpeggios and it was unbearable within a day.
//   - Low. Anything above about 800 Hz reads as a device beeping at you.
//   - Short. Under a tenth of a second of tone, plus the tail.
//   - Quiet enough to sit under whatever the user is already listening to.
//   - Pitch alone separates the three modes: higher for more awake.
//   - A small downward bend over the first few milliseconds. Struck things go
//     slightly sharp and settle, and without it a sine reads as electronic.
import Foundation

let rate = 44_100.0
let output = CommandLine.arguments.dropFirst().first ?? "Resources/Sounds"

/// One struck note. `decay` is the time constant, not the total length: the
/// tail is what keeps a sound from reading as a click.
struct Note {
    var frequency: Double
    var at: Double
    var decay: Double
    var level: Double
    /// Partials as (ratio to the fundamental, amplitude). Deliberately not
    /// whole-number harmonics only: a touch of something inharmonic is the
    /// difference between wood and a test tone.
    var partials: [(Double, Double)] = [(2.0, 0.075), (3.17, 0.035)]
    /// How far sharp the note starts, as a fraction, settling over 12 ms.
    var bend: Double = 0.02
}

func render(_ notes: [Note], length: Double) -> [Double] {
    var samples = [Double](repeating: 0, count: Int(length * rate))
    for note in notes {
        let start = Int(note.at * rate)
        for index in start..<samples.count {
            let time = Double(index - start) / rate
            // A few milliseconds of attack. Starting at full amplitude is the
            // click that makes a synthesised sound read as an error beep.
            let attack = min(time / 0.006, 1)
            let envelope = attack * exp(-time / note.decay)
            // Integrated, not instantaneous: multiplying the phase by a falling
            // frequency bends the whole note rather than its leading edge.
            let settle = 0.012
            let phase =
                note.frequency
                * (time + note.bend * settle * (1 - exp(-time / settle)))
            var value = sin(2 * .pi * phase)
            for (ratio, amplitude) in note.partials {
                value += amplitude * sin(2 * .pi * phase * ratio)
            }
            samples[index] += value * envelope * note.level
        }
    }
    // Five milliseconds of silence to arrive at, so the file cannot end on a
    // non-zero sample and pop.
    let fade = Int(0.005 * rate)
    for offset in 0..<min(fade, samples.count) {
        samples[samples.count - 1 - offset] *= Double(offset) / Double(fade)
    }
    return samples
}

func wav(_ samples: [Double]) -> Data {
    var data = Data()
    func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    put(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    put(16)
    put16(1)  // PCM
    put16(1)  // mono
    put(UInt32(rate))
    put(UInt32(rate) * 2)
    put16(2)
    put16(16)
    data.append(contentsOf: Array("data".utf8))
    put(bytes)
    for sample in samples {
        put16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32_000)))
    }
    return data
}

// Low, close together, and a minor third apart: far enough to tell apart with
// your back to the screen, near enough that the three are obviously one family.
let offNote = 466.16   // A#4
let autoNote = 587.33  // D5
let onNote = 739.99    // F#5

let sounds: [String: [Double]] = [
    // Auto. The mode Vigil is meant to be left in, so it is the plainest.
    "mode-auto": render([Note(frequency: autoNote, at: 0, decay: 0.075, level: 0.13)], length: 0.30),

    // Always on. Higher and held a little longer, because a deliberate override
    // should not sound exactly like handing control back.
    "mode-always": render(
        [
            Note(
                frequency: onNote, at: 0, decay: 0.095, level: 0.13,
                partials: [(2.0, 0.10), (3.17, 0.04)])
        ], length: 0.32),

    // Off. Lowest, shortest, quietest. Turning something off should not be the
    // loudest thing in the set.
    "mode-off": render(
        [
            Note(
                frequency: offNote, at: 0, decay: 0.065, level: 0.115,
                partials: [(2.0, 0.05)])
        ], length: 0.26),

    // A button did something. Barely there on purpose.
    "tick": render(
        [
            Note(
                frequency: onNote, at: 0, decay: 0.032, level: 0.085,
                partials: [(2.0, 0.04)], bend: 0.01)
        ], length: 0.14),

    // Thanks. The only one allowed to be a phrase rather than a note, because
    // it is the only moment that is about the person rather than the machine.
    "thanks": render(
        [
            Note(frequency: 523.25, at: 0, decay: 0.10, level: 0.11),
            Note(frequency: 659.25, at: 0.085, decay: 0.11, level: 0.11),
            Note(
                frequency: 783.99, at: 0.170, decay: 0.24, level: 0.12,
                partials: [(2.0, 0.09), (3.17, 0.03)]),
        ], length: 0.58),
]

try FileManager.default.createDirectory(
    atPath: output, withIntermediateDirectories: true)
for (name, samples) in sounds.sorted(by: { $0.key < $1.key }) {
    let url = URL(fileURLWithPath: "\(output)/\(name).wav")
    try wav(samples).write(to: url)
    print("wrote \(url.path) — \(String(format: "%.2f", Double(samples.count) / rate))s")
}
