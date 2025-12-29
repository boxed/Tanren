//
//  DeckDetailView.swift
//  Tanren
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: Deck
    @State private var showingPractice = false
    @State private var showingSettings = false
    @State private var showingAddCard = false
    @State private var selectedCard: Card?
    @State private var cardToEdit: Card?

    var dueCount: Int {
        SpacedRepetitionManager.selectCardsForPractice(from: deck).count
    }

    var body: some View {
        List {
            Section {
                Button(action: { showingPractice = true }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Practice")
                        Spacer()
                        if dueCount > 0 {
                            Text("\(dueCount) due")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(deck.cards.isEmpty)
            }

            Section("Cards (\(deck.cards.count))") {
                ForEach(deck.cards.sorted { $0.name < $1.name }) { card in
                    Button(action: { selectedCard = card }) {
                        CardRowView(card: card)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture {
                        cardToEdit = card
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteCard(card)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            cardToEdit = card
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button {
                            card.isSuspended.toggle()
                        } label: {
                            if card.isSuspended {
                                Label("Unsuspend", systemImage: "play.circle")
                            } else {
                                Label("Suspend", systemImage: "pause.circle")
                            }
                        }
                        .tint(card.isSuspended ? .green : .orange)
                    }
                }
            }
        }
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showingAddCard = true }) {
                        Label("Add Card", systemImage: "plus")
                    }
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPractice) {
            PracticeView(deck: deck)
        }
        .fullScreenCover(item: $selectedCard) { card in
            PracticeView(deck: deck, startingCard: card)
        }
        .sheet(isPresented: $showingSettings) {
            DeckSettingsView(deck: deck)
        }
        .sheet(isPresented: $showingAddCard) {
            AddCardView(deck: deck)
        }
        .sheet(item: $cardToEdit) { card in
            EditCardView(card: card)
        }
    }

    private func deleteCard(_ card: Card) {
        deck.cards.removeAll { $0.id == card.id }
        modelContext.delete(card)
    }
}

struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let deck: Deck

    @State private var side1 = ""
    @State private var side2 = ""
    @State private var url = ""
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var intervalTimerSeconds = ""
    @State private var intervalTimerReps = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Side 1", text: $side1)
                    if deck.side2Enabled {
                        TextField("Side 2", text: $side2)
                    }
                }

                if deck.imagesEnabled {
                    Section("Image") {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        }
                        Button(selectedImage == nil ? "Add Image" : "Change Image") {
                            showingImagePicker = true
                        }
                        if selectedImage != nil {
                            Button("Remove Image", role: .destructive) {
                                selectedImage = nil
                            }
                        }
                    }
                }

                if deck.urlEnabled {
                    Section("URL") {
                        TextField("URL", text: $url)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                    }
                }

                if deck.intervalTimersEnabled {
                    Section {
                        TextField("Seconds (comma separated)", text: $intervalTimerSeconds)
                            .keyboardType(.numbersAndPunctuation)
                        Stepper("Reps: \(intervalTimerReps)", value: $intervalTimerReps, in: 1...100)
                    } header: {
                        Text("Interval Timer")
                    } footer: {
                        Text("Example: \"10, 50\" with 3 reps creates: 10s, 50s, 10s, 50s, 10s, 50s")
                    }
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addCard()
                    }
                    .disabled(side1.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
        }
    }

    private func addCard() {
        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        let trimmedUrl = url.trimmingCharacters(in: .whitespaces)
        let card = Card(
            chord1: side1.trimmingCharacters(in: .whitespaces),
            chord2: side2.trimmingCharacters(in: .whitespaces),
            deck: deck,
            imageData: imageData,
            url: trimmedUrl.isEmpty ? nil : trimmedUrl
        )
        card.intervalTimerSeconds = intervalTimerSeconds.trimmingCharacters(in: .whitespaces)
        card.intervalTimerReps = intervalTimerReps
        deck.cards.append(card)
        modelContext.insert(card)
        dismiss()
    }
}

struct EditCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var card: Card

    @State private var side1: String
    @State private var side2: String
    @State private var url: String
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var intervalTimerSeconds: String
    @State private var intervalTimerReps: Int

    init(card: Card) {
        self.card = card
        _side1 = State(initialValue: card.chord1)
        _side2 = State(initialValue: card.chord2)
        _url = State(initialValue: card.url ?? "")
        _intervalTimerSeconds = State(initialValue: card.intervalTimerSeconds)
        _intervalTimerReps = State(initialValue: card.intervalTimerReps)
        if let imageData = card.imageData, let image = UIImage(data: imageData) {
            _selectedImage = State(initialValue: image)
        } else {
            _selectedImage = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Side 1", text: $side1)
                    if card.deck?.side2Enabled == true {
                        TextField("Side 2", text: $side2)
                    }
                }

                if card.deck?.imagesEnabled == true {
                    Section("Image") {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        }
                        Button(selectedImage == nil ? "Add Image" : "Change Image") {
                            showingImagePicker = true
                        }
                        if selectedImage != nil {
                            Button("Remove Image", role: .destructive) {
                                selectedImage = nil
                            }
                        }
                    }
                }

                if card.deck?.urlEnabled == true {
                    Section("URL") {
                        TextField("URL", text: $url)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                    }
                }

                if card.deck?.intervalTimersEnabled == true {
                    Section {
                        TextField("Seconds (comma separated)", text: $intervalTimerSeconds)
                            .keyboardType(.numbersAndPunctuation)
                        Stepper("Reps: \(intervalTimerReps)", value: $intervalTimerReps, in: 1...100)
                    } header: {
                        Text("Interval Timer")
                    } footer: {
                        Text("Example: \"10, 50\" with 3 reps creates: 10s, 50s, 10s, 50s, 10s, 50s")
                    }
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCard()
                    }
                    .disabled(side1.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
        }
    }

    private func saveCard() {
        card.chord1 = side1.trimmingCharacters(in: .whitespaces)
        card.chord2 = side2.trimmingCharacters(in: .whitespaces)
        card.name = card.chord2.isEmpty ? card.chord1 : "\(card.chord1) ↔ \(card.chord2)"
        card.imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        let trimmedUrl = url.trimmingCharacters(in: .whitespaces)
        card.url = trimmedUrl.isEmpty ? nil : trimmedUrl
        card.intervalTimerSeconds = intervalTimerSeconds.trimmingCharacters(in: .whitespaces)
        card.intervalTimerReps = intervalTimerReps
        dismiss()
    }
}

struct CardRowView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Text(card.chord1)
                        .font(.headline)
                    if !card.chord2.isEmpty {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.chord2)
                            .font(.headline)
                    }
                }

                Spacer()

                if card.isSuspended {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if card.isDue {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            HStack(spacing: 12) {
                if let bpm = card.comfortableBPM {
                    BPMBadge(label: "C", bpm: bpm, color: .green)
                }
                if let bpm = card.stretchBPM {
                    BPMBadge(label: "S", bpm: bpm, color: .yellow)
                }
                if let bpm = card.challengeBPM {
                    BPMBadge(label: "X", bpm: bpm, color: .red)
                }

                Spacer()

                if card.reviewCount > 0 {
                    Text("\(card.reviewCount) reviews")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(card.isSuspended ? 0.5 : 1.0)
    }
}

struct BPMBadge: View {
    let label: String
    let bpm: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
            Text("\(bpm)")
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .cornerRadius(4)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: {
            let deck = Deck(name: "Chords")
            let card = Card(chord1: "C", chord2: "D", deck: deck)
            card.comfortableBPM = 60
            card.stretchBPM = 80
            card.challengeBPM = 100
            deck.cards.append(card)
            return deck
        }())
    }
    .modelContainer(for: [Deck.self, Card.self], inMemory: true)
}
