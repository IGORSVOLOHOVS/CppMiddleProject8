#include "RefactorTool.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Lex/Lexer.h"
#include <unordered_set>

using namespace clang;
using namespace clang::ast_matchers;
using namespace clang::tooling;

static llvm::cl::OptionCategory ToolCategory("refactor-tool options");

class DescendantVisitor : public RecursiveASTVisitor<DescendantVisitor> {
public:
    explicit DescendantVisitor(const CXXRecordDecl *Base) : BaseClass(Base), HasDescendants(false) {}

    bool VisitCXXRecordDecl(CXXRecordDecl *D) {
        if (!D->hasDefinition()) {
            return true; 
        }

        if (D->isDerivedFrom(BaseClass)) {
            HasDescendants = true;
            return false; 
        }
        return true;
    }
    
    bool hasDescendants() const { return HasDescendants; }

private:
    const CXXRecordDecl *BaseClass;
    bool HasDescendants;
};

void RefactorHandler::run(const MatchFinder::MatchResult &Result) {
    auto& Diag = Result.Context->getDiagnostics();
    auto& SM = *Result.SourceManager;
    
    if (const auto *Dtor = Result.Nodes.getNodeAs<CXXDestructorDecl>("classDecl")) {
        handle_nv_dtor(Dtor, *Result.Context, Diag, SM);
    }

    if (const auto *Method = Result.Nodes.getNodeAs<CXXMethodDecl>("methodDecl")) {
        handle_miss_override(Method, Diag, SM);
    }

    if (const auto *LoopVar = Result.Nodes.getNodeAs<VarDecl>("loopVar")) {
        handle_crange_for(LoopVar, Diag, SM);
    }
}

void RefactorHandler::handle_nv_dtor(const CXXDestructorDecl *Dtor,
                                     ASTContext &Context,
                                     DiagnosticsEngine &Diag,
                                     SourceManager &SM) {
    if (!SM.isInMainFile(Dtor->getLocation()))
        return;

    const CXXRecordDecl* aClass = Dtor->getParent();
    const CXXRecordDecl* aClassDef = aClass->getDefinition();
    if (!aClassDef) return;

    DescendantVisitor Visitor(aClassDef);
    Visitor.TraverseDecl(Context.getTranslationUnitDecl());
    
    if (!Visitor.hasDescendants()) {
        return; 
    }
    
    unsigned loc = Dtor->getBeginLoc().getRawEncoding();
    if (virtualDtorLocations.count(loc))
        return;

    Rewrite.InsertText(Dtor->getLocation(), "virtual ");
    virtualDtorLocations.insert(loc);

    const unsigned DiagID = Diag.getCustomDiagID(
        DiagnosticsEngine::Warning,
        "Non-virtual destructor in base class; 'virtual' added");
    Diag.Report(Dtor->getLocation(), DiagID);
}

void RefactorHandler::handle_miss_override(const CXXMethodDecl *Method,
                                           DiagnosticsEngine &Diag,
                                           SourceManager &SM) {
    if (!SM.isInMainFile(Method->getLocation()))
        return;

    if (auto typeInfo = Method->getTypeSourceInfo()) {
        auto typeLoc = typeInfo->getTypeLoc().getAs<FunctionProtoTypeLoc>();
        if (!typeLoc.isNull()) {
            SourceLocation InsertionPoint = typeLoc.getRParenLoc();
            if (InsertionPoint.isValid()) {
                Rewrite.InsertTextAfterToken(InsertionPoint, " override");
                const unsigned DiagID = Diag.getCustomDiagID(
                    DiagnosticsEngine::Warning,
                    "Method overrides base method but is not marked; 'override' added");
                Diag.Report(Method->getLocation(), DiagID);
            }
        }
    }
}

void RefactorHandler::handle_crange_for(const VarDecl *LoopVar,
                                        DiagnosticsEngine &Diag,
                                        SourceManager &SM){
    if (!SM.isInMainFile(LoopVar->getLocation()))
        return;

    QualType VarType = LoopVar->getType();
    
    if (!VarType.isConstQualified() || VarType->isReferenceType() || VarType->isFundamentalType()) {
        return;
    }

    if (auto typeInfo = LoopVar->getTypeSourceInfo()) {
        TypeLoc typeLoc = typeInfo->getTypeLoc();
        SourceLocation InsertionPoint = typeLoc.getEndLoc();
        if (InsertionPoint.isValid()) {
            Rewrite.InsertTextAfterToken(InsertionPoint, "&");
            const unsigned DiagID = Diag.getCustomDiagID(
                DiagnosticsEngine::Warning,
               "Range-based for uses copying; added '&' reference");
            Diag.Report(LoopVar->getLocation(), DiagID);
        }
    }
}

auto NvDtorMatcher() {
    return cxxDestructorDecl(
        unless(isVirtual()), 
        unless(isImplicit())
    ).bind("classDecl");
}

auto NoOverrideMatcher()
{
    return cxxMethodDecl(
        isOverride(),
        unless(hasAttr(attr::Override)),
        unless(cxxDestructorDecl())
    ).bind("methodDecl");
}

auto NoRefConstVarInRangeLoopMatcher()
{
    return cxxForRangeStmt(
        hasLoopVariable(varDecl().bind("loopVar"))
    );
}

ComplexConsumer::ComplexConsumer(Rewriter &Rewrite) : Handler(Rewrite) {
    Finder.addMatcher(NvDtorMatcher(), &Handler);
    Finder.addMatcher(NoOverrideMatcher(), &Handler);
    Finder.addMatcher(NoRefConstVarInRangeLoopMatcher(), &Handler);
}

void ComplexConsumer::HandleTranslationUnit(ASTContext &Context) {
    Finder.matchAST(Context);
}

std::unique_ptr<ASTConsumer> CodeRefactorAction::CreateASTConsumer(CompilerInstance &CI,
                                                                 StringRef file) {
    RewriterForCodeRefactor.setSourceMgr(CI.getSourceManager(), CI.getLangOpts());
    return std::make_unique<ComplexConsumer>(RewriterForCodeRefactor);
}

bool CodeRefactorAction::BeginSourceFileAction( CompilerInstance &CI) {
    RewriterForCodeRefactor.setSourceMgr(CI.getSourceManager(), CI.getLangOpts());
    return true;
}

void CodeRefactorAction::EndSourceFileAction() {
    if (RewriterForCodeRefactor.overwriteChangedFiles()) {
        llvm::errs() << "Error applying changes to files.\n";
    }
}

int main(int argc, const char **argv) {
    auto ExpectedParser = CommonOptionsParser::create(argc, argv, ToolCategory);
    if (!ExpectedParser) {
        llvm::errs() << ExpectedParser.takeError();
        return 1;
    }
    CommonOptionsParser &OptionsParser = ExpectedParser.get();
    ClangTool Tool(OptionsParser.getCompilations(), OptionsParser.getSourcePathList());
    return Tool.run(newFrontendActionFactory<CodeRefactorAction>().get());
}