import Foundation

enum TastingTemplate: String, CaseIterable, Identifiable {
    case blank, bourbonBasics, blind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .bourbonBasics: "Bourbon basics"
        case .blind: "Blind flight"
        }
    }

    var blurb: String {
        switch self {
        case .blank: "One empty flight. Add your own pours."
        case .bourbonBasics: "Four styles side by side: wheated, high-rye, aged and barrel proof."
        case .blind: "Pours labeled A to D so nobody knows what's in the glass until the reveal."
        }
    }

    func menu(title: String, subtitle: String) -> TastingMenu {
        TastingMenu(title: title, subtitle: subtitle, flights: flights)
    }

    private var flights: [Flight] {
        switch self {
        case .blank:
            return [Flight(title: "Flight One", intro: "", pours: [Pour(name: "Pour 1")])]
        case .bourbonBasics:
            return [Flight(
                title: "Bourbon Basics",
                intro: "Same spirit, four different levers: the flavoring grain, age and proof. Taste left to right, lowest proof first.",
                pours: [
                    Pour(name: "Wheated bourbon", proof: 90, descriptor: "Wheat instead of rye",
                         nose: "Honey, vanilla, fresh bread", palate: "Caramel and butterscotch, soft", finish: "Short and sweet",
                         trivia: "Wheat as the flavoring grain trades pepper for softness."),
                    Pour(name: "High-rye bourbon", proof: 95, descriptor: "Spicy mash bill",
                         nose: "Mint, clove, orange peel", palate: "Rye spice over brown sugar", finish: "Peppery and dry",
                         trivia: "Compare this one directly with the wheater."),
                    Pour(name: "Aged bourbon", proof: 100, descriptor: "10+ years",
                         nose: "Leather, dark fruit, oak", palate: "Toffee and toasted nuts", finish: "Long, dry oak",
                         trivia: "Time in the barrel adds oak, color and depth."),
                    Pour(name: "Barrel proof bourbon", proof: 120, descriptor: "Uncut",
                         nose: "Dark cherry, cinnamon", palate: "Rich caramel, a lot of heat", finish: "Long. Try a few drops of water.",
                         trivia: "Bottled at the strength it came out of the barrel."),
                ]
            )]
        case .blind:
            return [Flight(
                title: "Blind Flight",
                intro: "Whoever pours fills in the real names after the reveal. Until then, trust your nose.",
                pours: ["A", "B", "C", "D"].map { Pour(name: "Pour \($0)") }
            )]
        }
    }
}

enum Copy {
    static let scoreWords = [1: "Not for me", 2: "Meh", 3: "Solid", 4: "Really good", 5: "Top shelf"]
}
