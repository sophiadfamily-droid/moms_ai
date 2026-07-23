import '../../models/life_context/life_context_domains.dart';

final class LifeContextAdapterRequest {
  const LifeContextAdapterRequest({
    required this.accountScopeId,
    required this.readAt,
  });

  final String accountScopeId;
  final DateTime readAt;
}

abstract interface class LifeContextDomainAdapter {
  LifeContextDomain get domain;

  Future<LifeContextDomainSection> load(LifeContextAdapterRequest request);
}
