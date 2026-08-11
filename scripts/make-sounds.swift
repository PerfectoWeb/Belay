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
//   - Nothing lasts longer than about a third of a second. These are
//     confirmations, not announcements.
//   - Nothing is loud. They sit under whatever the user is listening to.
//   - Pitch carries the meaning: rising for on, falling for off, level for a
//     thing that merely happened.
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
    /// Relative amplitudes of the harmonics above the fundamental. More of them
    /// reads as brighter and harder; two is a soft bell, four is a chime.
    var harmonics: [Double] = [0.28, 0.09]
}

func render(_ notes: [Note], length: Double) -> [Double] {
    var samples = [Double](repeating: 0, count: Int(length * rate))
    for note in notes {
        let start = Int(note.at * rate)
        for index in start..<samples.count {
            let time = Double(index - start) / rate
            // A few milliseconds of attack. Starting at full amplitude is the
            // click that makes a synthesised sound read as an error beep.
            let attack = min(time / 0.004, 1)
            let envelope = attack * exp(-time / note.decay)
            var value = sin(2 * .pi * note.frequency * time)
            for (harmonic, amplitude) in note.harmonics.enumerated() {
                value += amplitude * sin(2 * .pi * note.frequency * Double(harmonic + 2) * time)
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

// A pentatonic set: any two of these sound intentional together, which is what
// lets the five sounds below share a family without being arranged.
let c6 = 1046.5
let d6 = 1174.7
let e6 = 1318.5
let g6 = 1568.0
let a6 = 1760.0

let sounds: [String: [Double]] = [
    // Auto: rising, and unhurried. This is the mode Vigil is meant to be left
    // in, so it is the least eventful of the three.
    "mode-auto": render(
        [
            Note(frequency: e6, at: 0, decay: 0.10, level: 0.20),
            Note(frequency: a6, at: 0.055, decay: 0.16, level: 0.20),
        ], length: 0.34),

    // Always on: one note, brighter and held. A deliberate override should
    // sound like a switch being thrown, not like a suggestion.
    "mode-always": render(
        [
            Note(
                frequency: a6, at: 0, decay: 0.20, level: 0.22,
                harmonics: [0.34, 0.16, 0.06])
        ], length: 0.34),

    // Off: the same interval as Auto, downwards, quieter and shorter. Turning
    // something off should not be the loudest thing in the set.
    "mode-off": render(
        [
            Note(frequency: a6, at: 0, decay: 0.09, level: 0.17),
            Note(frequency: e6, at: 0.055, decay: 0.13, level: 0.17),
        ], length: 0.30),

    // A check that found nothing to say. Level pitch, barely there: it marks
    // that the button did something and then gets out of the way.
    "tick": render(
        [Note(frequency: g6, at: 0, decay: 0.05, level: 0.13, harmonics: [0.2])],
        length: 0.14),

    // Thanks. The only sound here allowed to be a phrase rather than a note,
    // because it is the only moment that is about the person rather than the
    // machine.
    "thanks": render(
        [
            Note(frequency: c6, at: 0, decay: 0.13, level: 0.18),
            Note(frequency: e6, at: 0.075, decay: 0.15, level: 0.18),
            Note(frequency: g6, at: 0.150, decay: 0.30, level: 0.20, harmonics: [0.3, 0.12, 0.05]),
            Note(frequency: d6 * 2, at: 0.150, decay: 0.34, level: 0.06, harmonics: []),
        ], length: 0.62),
]

try FileManager.default.createDirectory(
    atPath: output, withIntermediateDirectories: true)
for (name, samples) in sounds.sorted(by: { $0.key < $1.key }) {
    let url = URL(fileURLWithPath: "\(output)/\(name).wav")
    try wav(samples).write(to: url)
    print("wrote \(url.path) — \(String(format: "%.2f", Double(samples.count) / rate))s")
}
