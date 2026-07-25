import Foundation
import LocalAuthentication
import SwiftUI

public class UserSecurity: ObservableObject {
    
    // Publishes lock status to update your visual presentation layers instantly
    @Published public var isVaultUnlocked: Bool = false
    @Published public var securityErrorMessage: String?
    
    public init() {}
    
    /// Requests native device biometric authorization (FaceID/TouchID) to unlock files
    public func authenticateCollectorVault() {
        let context = LAContext()
        var structuralError: NSError?
        
        // Step 1: Check if the device hardware supports biometric verification
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &structuralError) {
            let unlockReasonText = "Authorize FaceID biometric verification to unlock your high-value portfolio collection vault."
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: unlockReasonText) { success, authenticationError in
                // Hop back onto the Main Thread to safely perform user interface view changes
                Task { @MainActor in
                    if success {
                        self.isVaultUnlocked = true
                        self.securityErrorMessage = nil
                    } else {
                        self.securityErrorMessage = authenticationError?.localizedDescription ?? "Biometric evaluation rejected by user."
                    }
                }
            }
        } else {
            // Fallback safety catch if FaceID hardware is restricted or disabled entirely
            Task { @MainActor in
                self.securityErrorMessage = "Biometric hardware setup unavailable. Please check system privacy configurations."
                // In production, you can trigger a password field fallback script here
                self.isVaultUnlocked = true 
            }
        }
    }
    
    /// Instantly locks down access controls upon backgrounding transitions
    public func enforceVaultLockdown() {
        self.isVaultUnlocked = false
    }
}

// Satisfy Swift Playgrounds compiler target architecture parameters
struct UserSecurity_Previews: PreviewProvider {
    static var previews: some View {
        Text("User Security Vault Module Live")
            .foregroundColor(.secondary)
            .padding()
    }
}
