#pragma once
#include "clang/ASTMatchers/ASTMatchers.h"
#include "clang/ASTMatchers/ASTMatchFinder.h"
#include "clang/Frontend/FrontendActions.h"
#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/Tooling/Tooling.h"
#include "clang/Tooling/Refactoring.h"
#include "clang/Rewrite/Core/Rewriter.h"
#include "llvm/Support/CommandLine.h"

#include <unordered_set>

class RefactorHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
public:
    explicit RefactorHandler(clang::Rewriter &Rewrite) : Rewrite(Rewrite) {}
    virtual void run(const clang::ast_matchers::MatchFinder::MatchResult &Result) override;

private:
    void handle_nv_dtor(const clang::CXXDestructorDecl *Dtor,
                        clang::ASTContext &Context,
                        clang::DiagnosticsEngine &Diag,
                        clang::SourceManager &SM);

    void handle_miss_override(const clang::CXXMethodDecl *Method,
                              clang::DiagnosticsEngine &Diag,
                              clang::SourceManager &SM);

    void handle_crange_for(const clang::VarDecl *LoopVar,
                           clang::DiagnosticsEngine &Diag,
                           clang::SourceManager &SM);
private:
    clang::Rewriter &Rewrite;
    std::unordered_set<unsigned> virtualDtorLocations;
};

class ComplexConsumer : public clang::ASTConsumer {
public:
    explicit ComplexConsumer(clang::Rewriter &Rewrite);
    void HandleTranslationUnit(clang::ASTContext &Context) override;
private:
    RefactorHandler Handler;
    clang::ast_matchers::MatchFinder Finder;
};

class CodeRefactorAction : public clang::ASTFrontendAction {
public:
    virtual std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(clang::CompilerInstance &CI, clang::StringRef file) override;
    virtual bool BeginSourceFileAction(clang::CompilerInstance &CI) override;
    virtual void EndSourceFileAction() override;

private:
    clang::Rewriter RewriterForCodeRefactor;
};