import SwiftUI

struct EditActionsBar: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 6) {
            Divider()

            VStack(spacing: 6) {
                // Undo / Redo / Reset
                HStack(spacing: 6) {
                    Button(action: { viewModel.undoEdit() }) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(!viewModel.canUndo)

                    Button(action: { viewModel.redoEdit() }) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(!viewModel.canRedo)

                    Button(action: {
                        viewModel.pushUndoSnapshot()
                        viewModel.editPayload.reset()
                        viewModel.schedulePreviewRender()
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(!viewModel.editPayload.hasAdjustments)
                }

                // Save / Export
                Button(action: {
                    guard let photo = viewModel.selectedPhoto else { return }
                    viewModel.saveEditsToOriginal(photo: photo, payload: viewModel.editPayload)
                }) {
                    Label("Save to Original", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.editPayload.hasAdjustments)

                Button(action: {
                    guard let photo = viewModel.selectedPhoto else { return }
                    viewModel.exportEditedCopy(photo: photo, payload: viewModel.editPayload)
                }) {
                    Label("Export Edited Copy", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.editPayload.hasAdjustments)

                // Done
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() }
                } label: {
                    Label("Done Editing", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .background(.bar)
    }
}
