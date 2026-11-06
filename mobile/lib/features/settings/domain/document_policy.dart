class DocumentPolicy {
  const DocumentPolicy._();

  static const int healthConditionMaxLength = 80;

  static bool canUpload(String? verificationStatus) =>
      verificationStatus != 'verified' && verificationStatus != 'approved';
}
