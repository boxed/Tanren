//
//  TimeSignatureTests.swift
//  TanrenTests
//

import Testing
@testable import Tanren

struct TimeSignatureTests {

    @Test func theDownbeatIsAlwaysStrongest() {
        for signature in TimeSignature.allCases {
            #expect(signature.accent(onBeat: 1) == .strong)
        }
    }

    @Test func simpleMetersHaveOnlyADownbeat() {
        for signature in [TimeSignature.twoFour, .threeFour, .fourFour] {
            for beat in 2...signature.beatsPerMeasure {
                #expect(signature.accent(onBeat: beat) == .weak)
            }
        }
    }

    @Test func compoundAndOddMetersAccentTheSecondGroup() {
        #expect(TimeSignature.sixEight.accent(onBeat: 4) == .medium)
        #expect(TimeSignature.sevenEight.accent(onBeat: 4) == .medium)
        #expect(TimeSignature.fiveFour.accent(onBeat: 4) == .medium)
        #expect(TimeSignature.sixEight.accent(onBeat: 5) == .weak)
    }

    @Test func notationRoundTripsThroughStorage() {
        for signature in TimeSignature.allCases {
            #expect(TimeSignature(rawValue: signature.rawValue) == signature)
        }
    }

    @Test func unknownStoredNotationFallsBackToFourFour() {
        let card = Card(chord1: "C", chord2: "G")
        #expect(card.timeSignature == .fourFour)
        card.timeSignatureRaw = "13/16"
        #expect(card.timeSignature == .fourFour)
        card.timeSignature = .threeFour
        #expect(card.timeSignatureRaw == "3/4")
    }
}
